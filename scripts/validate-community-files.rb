# frozen_string_literal: true

require "pathname"
require "uri"
require "yaml"

DEFAULT_ROOT = Pathname(__dir__).join("..").expand_path
ROOT = Pathname(ENV.fetch("COMMUNITY_FILES_ROOT", DEFAULT_ROOT.to_s)).expand_path
ISSUE_TEMPLATE_DIRECTORY = ".github/ISSUE_TEMPLATE"
REQUIRED_FILES = %w[
  CODE_OF_CONDUCT.md
  CONTRIBUTING.md
  README.md
  SECURITY.md
  SUPPORT.md
  .github/ISSUE_TEMPLATE/config.yml
  .github/pull_request_template.md
  profile/README.md
].freeze
ISSUE_FORM_FIELD_TYPES = %w[checkboxes dropdown input markdown textarea upload].freeze
ISSUE_FORM_TOP_LEVEL_KEYS = %w[assignees body description labels name projects title type].freeze
ISSUE_FORM_BODY_KEYS = %w[attributes id type validations].freeze
ISSUE_FORM_ATTRIBUTE_KEYS = {
  "checkboxes" => %w[description label options],
  "dropdown" => %w[default description label multiple options],
  "input" => %w[description label placeholder value],
  "markdown" => %w[value],
  "textarea" => %w[description label placeholder render value],
  "upload" => %w[description label]
}.freeze
ISSUE_FORM_VALIDATION_KEYS = {
  "checkboxes" => %w[required],
  "dropdown" => %w[required],
  "input" => %w[required],
  "markdown" => [],
  "textarea" => %w[required],
  "upload" => %w[accept required]
}.freeze
ISSUE_FORM_CHECKBOX_OPTION_KEYS = %w[label required].freeze
ISSUE_FORM_OPTIONAL_TEXT_ATTRIBUTE_KEYS = %w[description placeholder render value].freeze
ISSUE_FORM_UPLOAD_EXTENSIONS = %w[
  .csv .docx .gif .gz .jpeg .jpg .js .json .log .mov .mp4 .pdf .png .pptx
  .py .svg .tar.gz .ts .txt .webm .webp .xlsx .zip
].freeze
ISSUE_TEMPLATE_CONFIG_KEYS = %w[blank_issues_enabled contact_links].freeze
ISSUE_TEMPLATE_CONTACT_LINK_KEYS = %w[about name url].freeze
ISSUE_FORM_PROJECT_PATTERN = /\A[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\/[1-9]\d*\z/
ISSUE_FORM_FORBIDDEN_LABEL_PATTERN = /\bpasswords?\b/i
HTML_ANCHOR_HREF_PATTERN = /
  <a\b
  (?:
    \s+
    (?!href\b)
    [^\s"'=<>`\/]+
    (?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?
  )*
  \s+href\s*=\s*
  (?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))
/ix

def issue_form_reference(value)
  return unless value.is_a?(String)

  value
    .unicode_normalize(:nfkd)
    .encode("ASCII", invalid: :replace, undef: :replace, replace: "")
    .downcase
    .gsub(/[^a-z0-9_-]+/, "-")
    .gsub(/-+/, "-")
    .gsub(/\A-+|-+\z/, "")
end

def normalized_issue_form_choice(value)
  value.strip.unicode_normalize(:nfkc).downcase
end

def html_anchor_targets(contents)
  contents.scan(HTML_ANCHOR_HREF_PATTERN).map do |captures|
    captures.compact.first
  end
end

def duplicate_yaml_mapping_keys(node, duplicates = [])
  children = node.children
  return duplicates unless children

  if node.is_a?(Psych::Nodes::Mapping)
    seen_keys = {}
    children.each_slice(2) do |key_node, value_node|
      if key_node.is_a?(Psych::Nodes::Scalar)
        key = key_node.value
        duplicates << key if seen_keys.key?(key)
        seen_keys[key] = true
      end

      duplicate_yaml_mapping_keys(key_node, duplicates)
      duplicate_yaml_mapping_keys(value_node, duplicates)
    end
  else
    children.each { |child| duplicate_yaml_mapping_keys(child, duplicates) }
  end

  duplicates
end

def path_inside_repository?(path)
  repository_path = ROOT.realpath
  resolved_path = path.realpath

  resolved_path == repository_path ||
    resolved_path.to_s.start_with?("#{repository_path}#{File::SEPARATOR}")
rescue SystemCallError
  false
end

errors = []

REQUIRED_FILES.each do |relative_path|
  path = ROOT.join(relative_path)
  unless path.file?
    errors << "Missing required file: #{relative_path}"
    next
  end

  errors << "Required file resolves outside repository: #{relative_path}" unless path_inside_repository?(path)
end

yaml_files = ROOT.glob(".github/**/*.{yml,yaml}").sort
yaml_documents = {}

ROOT.glob("#{ISSUE_TEMPLATE_DIRECTORY}/**/*.{md,yml,yaml}").sort.each do |path|
  relative_path = path.relative_path_from(ROOT).to_s
  next if Pathname(relative_path).dirname.to_s == ISSUE_TEMPLATE_DIRECTORY

  errors << "Issue template must be stored directly in #{ISSUE_TEMPLATE_DIRECTORY}: #{relative_path}"
end

yaml_files.each do |path|
  relative_path = path.relative_path_from(ROOT).to_s

  unless path_inside_repository?(path)
    errors << "YAML file resolves outside repository: #{relative_path}"
    next
  end

  begin
    contents = path.read
    yaml_stream = Psych.parse_stream(contents)
    unless yaml_stream.children.length == 1
      errors << "YAML file must contain exactly one document: #{relative_path}"
    end
    duplicate_yaml_mapping_keys(yaml_stream).uniq.each do |key|
      errors << "Duplicate YAML key #{key} in #{relative_path}"
    end
    yaml_documents[relative_path] = YAML.safe_load(contents, aliases: false)
  rescue Psych::Exception => error
    errors << "Invalid YAML in #{relative_path}: #{error.message.lines.first.strip}"
  end
end

yaml_files.each do |path|
  relative_path = path.relative_path_from(ROOT).to_s
  next unless relative_path.start_with?(".github/ISSUE_TEMPLATE/")
  next unless path.extname == ".yaml"

  errors << "Issue form #{relative_path} must use the .yml extension"
end

issue_forms = yaml_documents.select do |relative_path, _document|
  relative_path.start_with?(".github/ISSUE_TEMPLATE/") &&
    relative_path.end_with?(".yml") &&
    !relative_path.end_with?("/config.yml") &&
    Pathname(relative_path).dirname.to_s == ISSUE_TEMPLATE_DIRECTORY
end

issue_forms.each do |relative_path, form|
  unless form.is_a?(Hash)
    errors << "Issue form must be a mapping: #{relative_path}"
    next
  end

  (form.keys - ISSUE_FORM_TOP_LEVEL_KEYS).each do |key|
    errors << "Issue form #{relative_path} has unpermitted top-level key #{key}"
  end

  %w[name description].each do |field|
    value = form[field]
    errors << "Issue form #{relative_path} needs #{field}" unless value.is_a?(String) && !value.strip.empty?
  end

  name = form["name"]
  if name.is_a?(String) && !name.strip.empty? && name.strip.length <= 3
    errors << "Issue form #{relative_path} name must contain more than 3 characters"
  end

  if form.key?("title")
    if !form["title"].is_a?(String)
      errors << "Issue form #{relative_path} title must be a string"
    elsif form["title"].strip.empty?
      errors << "Issue form #{relative_path} title must be a non-empty string"
    end
  end

  if form.key?("type")
    if !form["type"].is_a?(String)
      errors << "Issue form #{relative_path} type must be a string"
    elsif form["type"].strip.empty?
      errors << "Issue form #{relative_path} type must be a non-empty string"
    end
  end

  %w[labels assignees].each do |field|
    next unless form.key?(field)

    value = form[field]
    valid = if value.is_a?(String)
      value.split(",", -1).all? { |item| !item.strip.empty? }
    elsif value.is_a?(Array)
      value.all? { |item| item.is_a?(String) && !item.strip.empty? }
    else
      false
    end

    unless valid
      errors << "Issue form #{relative_path} #{field} must be a string or list of non-empty strings"
    end
  end

  if form.key?("projects")
    value = form["projects"]
    projects = if value.is_a?(String)
      value.split(",", -1)
    elsif value.is_a?(Array)
      value
    end
    valid = projects&.any? && projects.all? do |project|
      project.is_a?(String) && project.strip.match?(ISSUE_FORM_PROJECT_PATTERN)
    end

    unless valid
      errors << "Issue form #{relative_path} projects must use PROJECT-OWNER/PROJECT-NUMBER values"
    end
  end

  body = form["body"]
  unless body.is_a?(Array) && !body.empty?
    errors << "Issue form #{relative_path} needs a non-empty body"
    next
  end

  has_response_field = body.any? do |field|
    field.is_a?(Hash) &&
      ISSUE_FORM_FIELD_TYPES.include?(field["type"]) &&
      field["type"] != "markdown"
  end
  errors << "Issue form #{relative_path} needs at least one response field" unless has_response_field

  body.each_with_index do |field, index|
    field_number = index + 1

    unless field.is_a?(Hash)
      errors << "Issue form #{relative_path} body field #{field_number} must be a mapping"
      next
    end

    (field.keys - ISSUE_FORM_BODY_KEYS).each do |key|
      errors << "Issue form #{relative_path} body field #{field_number} has unpermitted key #{key}"
    end

    type = field["type"]
    unless ISSUE_FORM_FIELD_TYPES.include?(type)
      errors << "Issue form #{relative_path} body field #{field_number} has unsupported type #{type}"
    end

    if type == "markdown" && field.key?("id")
      errors << "Issue form #{relative_path} body field #{field_number} markdown cannot define an id"
    elsif type != "markdown" && field.key?("id")
      id = field["id"]
      unless id.is_a?(String) && id.match?(/\A[A-Za-z0-9_-]+\z/)
        errors << "Issue form #{relative_path} body field #{field_number} has invalid id #{id}"
      end
    end

    attributes = field["attributes"]
    unless attributes.is_a?(Hash)
      errors << "Issue form #{relative_path} body field #{field_number} attributes must be a mapping"
      next
    end

    permitted_attributes = ISSUE_FORM_ATTRIBUTE_KEYS.fetch(type, [])
    (attributes.keys - permitted_attributes).each do |key|
      errors << "Issue form #{relative_path} body field #{field_number} #{type} has unpermitted attribute #{key}"
    end

    required_attribute = type == "markdown" ? "value" : "label"
    attribute_value = attributes[required_attribute]
    unless attribute_value.is_a?(String) && !attribute_value.strip.empty?
      errors << "Issue form #{relative_path} body field #{field_number} #{type} needs a #{required_attribute}"
    end
    if %w[input textarea].include?(type) &&
        attribute_value.is_a?(String) &&
        attribute_value.match?(ISSUE_FORM_FORBIDDEN_LABEL_PATTERN)
      errors << "Issue form #{relative_path} body field #{field_number} #{type} label contains forbidden word password"
    end

    ISSUE_FORM_OPTIONAL_TEXT_ATTRIBUTE_KEYS.each do |key|
      next if key == required_attribute || !attributes.key?(key)

      value = attributes[key]
      unless value.is_a?(String) && !value.strip.empty?
        errors << "Issue form #{relative_path} body field #{field_number} #{type} #{key} must be a non-empty string"
      end
    end

    if type == "dropdown"
      multiple = attributes["multiple"]
      if attributes.key?("multiple") && ![true, false].include?(multiple)
        errors << "Issue form #{relative_path} body field #{field_number} dropdown multiple must be a boolean"
      end

      options = attributes["options"]
      if !options.is_a?(Array) || options.empty?
        errors << "Issue form #{relative_path} body field #{field_number} dropdown needs options"
      else
        seen_options = {}
        options.each_with_index do |option, option_index|
          unless option.is_a?(String) && !option.strip.empty?
            errors << "Issue form #{relative_path} body field #{field_number} dropdown option #{option_index + 1} must be a non-empty string"
            next
          end

          displayed_option = option.strip
          normalized_option = normalized_issue_form_choice(option)
          if normalized_option == "none"
            errors << "Issue form #{relative_path} body field #{field_number} dropdown uses reserved option none"
          end
          if attributes.key?("default") && normalized_option == "n/a"
            errors << "Issue form #{relative_path} body field #{field_number} dropdown uses reserved option n/a"
          end
          if seen_options[normalized_option]
            errors << "Issue form #{relative_path} body field #{field_number} dropdown repeats option #{displayed_option}"
          end
          seen_options[normalized_option] = true
        end
      end

      if attributes.key?("default")
        default = attributes["default"]
        valid_default = default.is_a?(Integer) &&
          options.is_a?(Array) &&
          default >= 0 &&
          default < options.length
        unless valid_default
          errors << "Issue form #{relative_path} body field #{field_number} dropdown default must index an option"
        end
      end
    elsif type == "checkboxes"
      options = attributes["options"]
      if !options.is_a?(Array) || options.empty?
        errors << "Issue form #{relative_path} body field #{field_number} checkboxes need options"
      else
        seen_labels = {}
        options.each_with_index do |option, option_index|
          unless option.is_a?(Hash)
            errors << "Issue form #{relative_path} body field #{field_number} checkbox option #{option_index + 1} must be a mapping"
            next
          end

          (option.keys - ISSUE_FORM_CHECKBOX_OPTION_KEYS).each do |key|
            errors << "Issue form #{relative_path} body field #{field_number} checkbox option #{option_index + 1} has unpermitted key #{key}"
          end

          label = option["label"]
          unless label.is_a?(String) && !label.strip.empty?
            errors << "Issue form #{relative_path} body field #{field_number} checkbox option #{option_index + 1} needs label"
          else
            normalized_label = label.strip
            if seen_labels[normalized_label]
              errors << "Issue form #{relative_path} body field #{field_number} checkbox repeats label #{normalized_label}"
            end
            seen_labels[normalized_label] = true
          end

          required = option["required"]
          if !required.nil? && ![true, false].include?(required)
            errors << "Issue form #{relative_path} body field #{field_number} checkbox option #{option_index + 1} required must be a boolean"
          end
        end
      end
    end

    validations = field["validations"]
    if !validations.nil? && !validations.is_a?(Hash)
      errors << "Issue form #{relative_path} body field #{field_number} validations must be a mapping"
    elsif validations.is_a?(Hash)
      permitted_validations = ISSUE_FORM_VALIDATION_KEYS.fetch(type, [])
      (validations.keys - permitted_validations).each do |key|
        errors << "Issue form #{relative_path} body field #{field_number} #{type} has unpermitted validation #{key}"
      end

      if validations.key?("required") && ![true, false].include?(validations["required"])
        errors << "Issue form #{relative_path} body field #{field_number} required must be a boolean"
      end

      if type == "upload" && validations.key?("accept")
        accept = validations["accept"]
        if !accept.is_a?(String) || accept.strip.empty?
          errors << "Issue form #{relative_path} body field #{field_number} upload accept must be a comma-separated extension list"
        else
          accept.split(",", -1).map(&:strip).uniq.each do |extension|
            unless ISSUE_FORM_UPLOAD_EXTENSIONS.include?(extension.downcase)
              errors << "Issue form #{relative_path} body field #{field_number} upload accept contains unsupported extension #{extension}"
            end
          end
        end
      end
    end
  end

  field_ids = body.map do |field|
    next unless field.is_a?(Hash)

    field["id"]
  end.compact
  duplicates = field_ids.group_by(&:itself).select { |_id, values| values.length > 1 }.keys
  duplicates.each do |id|
    errors << "Issue form #{relative_path} repeats field id #{id}"
  end

  field_references = body.flat_map do |field|
    next [] unless field.is_a?(Hash) && field["type"] != "markdown"

    attributes = field["attributes"]
    next [] unless attributes.is_a?(Hash)

    references = [field["id"] || issue_form_reference(attributes["label"])]
    if field["type"] == "checkboxes" && attributes["options"].is_a?(Array)
      references.concat(attributes["options"].map do |option|
        next unless option.is_a?(Hash)

        issue_form_reference(option["label"])
      end.compact)
    end
    references.compact.reject(&:empty?)
  end
  duplicate_references = field_references
    .group_by(&:itself)
    .select { |_reference, values| values.length > 1 }
    .keys
  duplicate_references.each do |reference|
    errors << "Issue form #{relative_path} repeats field reference #{reference}"
  end
end

issue_template_names = issue_forms.each_with_object([]) do |(relative_path, form), names|
  next unless form.is_a?(Hash)

  name = form["name"]
  next unless name.is_a?(String) && !name.strip.empty?

  names << [relative_path, name.strip]
end
ROOT.glob("#{ISSUE_TEMPLATE_DIRECTORY}/*.md").sort.each do |path|
  next unless path_inside_repository?(path)

  relative_path = path.relative_path_from(ROOT).to_s
  lines = path.read.lines
  unless lines.first&.strip == "---"
    errors << "Classic issue template #{relative_path} needs YAML front matter"
    next
  end

  closing_index = lines.drop(1).index { |line| line.strip == "---" }
  unless closing_index
    errors << "Classic issue template #{relative_path} has unterminated YAML front matter"
    next
  end

  begin
    front_matter = lines[1, closing_index].join
    duplicate_yaml_mapping_keys(Psych.parse_stream(front_matter)).uniq.each do |key|
      errors << "Duplicate YAML front matter key #{key} in #{relative_path}"
    end
    metadata = YAML.safe_load(front_matter, aliases: false)
  rescue Psych::Exception => error
    errors << "Invalid YAML front matter in #{relative_path}: #{error.message.lines.first.strip}"
    next
  end
  unless metadata.is_a?(Hash)
    errors << "Classic issue template #{relative_path} front matter must be a mapping"
    next
  end

  %w[name about].each do |field|
    value = metadata[field]
    unless value.is_a?(String) && !value.strip.empty?
      errors << "Classic issue template #{relative_path} needs #{field}"
    end
  end

  name = metadata["name"]
  next unless name.is_a?(String) && !name.strip.empty?

  issue_template_names << [relative_path, name.strip]
end
issue_template_names.group_by { |_relative_path, name| name.unicode_normalize(:nfkc).downcase }.each_value do |entries|
  next unless entries.length > 1

  paths = entries.map(&:first).join(", ")
  errors << "Issue template name #{entries.first.last} is repeated in #{paths}"
end

issue_template_config = yaml_documents[".github/ISSUE_TEMPLATE/config.yml"]

if issue_template_config.is_a?(Hash)
  (issue_template_config.keys - ISSUE_TEMPLATE_CONFIG_KEYS).each do |key|
    errors << "Issue template config has unpermitted key #{key}"
  end

  blank_issues_enabled = issue_template_config["blank_issues_enabled"]
  unless [true, false].include?(blank_issues_enabled)
    errors << "Issue template config blank_issues_enabled must be a boolean"
  end

  contact_links = issue_template_config["contact_links"]
  unless contact_links.is_a?(Array)
    errors << "Issue template config contact_links must be a list"
    contact_links = []
  end

  contact_links.each_with_index do |link, index|
    unless link.is_a?(Hash)
      errors << "Issue template contact link #{index + 1} must be a mapping"
      next
    end

    (link.keys - ISSUE_TEMPLATE_CONTACT_LINK_KEYS).each do |key|
      errors << "Issue template contact link #{index + 1} has unpermitted key #{key}"
    end

    %w[name about].each do |field|
      value = link[field]
      unless value.is_a?(String) && !value.strip.empty?
        errors << "Issue template contact link #{index + 1} needs #{field}"
      end
    end

    url = link["url"]
    uri = nil
    valid_url = begin
      uri = URI.parse(url.to_s)
      url.is_a?(String) && uri.scheme == "https" && !uri.host.to_s.empty?
    rescue URI::InvalidURIError
      false
    end
    unless valid_url
      errors << "Issue template contact link #{index + 1} needs an HTTPS URL"
    else
      errors << "Issue template contact link #{index + 1} URL must not include user information" if uri.userinfo
    end
  end
elsif ROOT.join(".github/ISSUE_TEMPLATE/config.yml").file?
  errors << "Issue template config must be a mapping"
end

markdown_files = ROOT.glob("**/*.md", File::FNM_DOTMATCH).reject do |path|
  path.each_filename.any? { |part| part == ".git" }
end.sort
markdown_link_count = 0

markdown_files.each do |path|
  relative_path = path.relative_path_from(ROOT).to_s

  unless path_inside_repository?(path)
    errors << "Markdown file resolves outside repository: #{relative_path}"
    next
  end

  contents = path.read
  inline_targets = contents.scan(/\[[^\]]*\]\(([^)]*)\)/).flatten
  autolink_targets = contents.scan(
    /(?<!\]\()<((?:https?|mailto):[^<>\r\n]*)>/i
  ).flatten
  html_targets = html_anchor_targets(contents)
  reference_definitions = contents.scan(
    /^[ \t]{0,3}\[(?!\^)([^\]\n]+)\]:[ \t]*(?:<([^>\n]+)>|(\S+))/
  )
  reference_targets = reference_definitions.map do |_label, angle_target, bare_target|
    angle_target || bare_target
  end
  normalize_reference = lambda do |value|
    value.strip.gsub(/[ \t\r\n]+/, " ").downcase
  end
  defined_references = reference_definitions.map do |label, _angle_target, _bare_target|
    normalize_reference.call(label)
  end
  contents.scan(/\[([^\]\n]+)\]\[([^\]\n]*)\]/).each do |text, label|
    reference = label.empty? ? text : label
    next if defined_references.include?(normalize_reference.call(reference))

    errors << "Undefined Markdown link reference in #{relative_path}: #{reference}"
  end

  (inline_targets + autolink_targets + html_targets + reference_targets).each do |raw_target|
    target = raw_target.strip.sub(/\s+"[^"]*"\z/, "").delete_prefix("<").delete_suffix(">")
    if target.empty?
      errors << "Empty Markdown link target in #{relative_path}"
      next
    end
    next if target.start_with?("#")

    markdown_link_count += 1

    if target.match?(/\Ahttps?:\/\//)
      uri = URI.parse(target)
      errors << "External link lacks a host in #{relative_path}: #{target}" unless uri.host
      unless uri.scheme == "https"
        errors << "External link must use HTTPS in #{relative_path}: #{target}"
      end
      if uri.userinfo
        errors << "External link includes user information in #{relative_path}: #{target}"
      end
      next
    end

    if target.start_with?("mailto:")
      raw_recipient = target.delete_prefix("mailto:").partition("?").first
      recipient = URI::DEFAULT_PARSER.unescape(raw_recipient).strip
      if recipient.empty?
        errors << "Mail link needs a recipient in #{relative_path}: #{target}"
      end
      next
    end

    if target.match?(/\A[a-z][a-z0-9+.-]*:/i)
      errors << "Unsupported link scheme in #{relative_path}: #{target}"
      next
    end

    file_target = URI::DEFAULT_PARSER.unescape(target.split("#", 2).first)
    destination = if file_target.start_with?("/")
      ROOT.join(file_target.delete_prefix("/"))
    else
      path.dirname.join(file_target)
    end.cleanpath

    inside_repository = destination == ROOT ||
      destination.to_s.start_with?("#{ROOT}#{File::SEPARATOR}")
    unless inside_repository
      errors << "Relative link escapes repository in #{relative_path}: #{target}"
      next
    end

    unless destination.exist?
      errors << "Broken relative link in #{relative_path}: #{target}"
      next
    end

    unless path_inside_repository?(destination)
      errors << "Relative link escapes repository in #{relative_path}: #{target}"
    end
  rescue URI::InvalidURIError
    errors << "Invalid link in #{relative_path}: #{target}"
  end
end

unless errors.empty?
  warn errors.join("\n")
  exit 1
end

puts "Validated #{yaml_files.length} YAML files and #{markdown_link_count} Markdown links."
