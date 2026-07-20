# frozen_string_literal: true

require "pathname"
require "uri"
require "yaml"

DEFAULT_ROOT = Pathname(__dir__).join("..").expand_path
ROOT = Pathname(ENV.fetch("COMMUNITY_FILES_ROOT", DEFAULT_ROOT.to_s)).expand_path
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
ISSUE_FORM_PROJECT_PATTERN = /\A[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\/[1-9]\d*\z/

errors = []

REQUIRED_FILES.each do |relative_path|
  path = ROOT.join(relative_path)
  errors << "Missing required file: #{relative_path}" unless path.file?
end

yaml_files = ROOT.glob(".github/**/*.{yml,yaml}").sort
yaml_documents = {}

yaml_files.each do |path|
  relative_path = path.relative_path_from(ROOT).to_s

  begin
    yaml_documents[relative_path] = YAML.safe_load(path.read, aliases: false)
  rescue Psych::Exception => error
    errors << "Invalid YAML in #{relative_path}: #{error.message.lines.first.strip}"
  end
end

issue_forms = yaml_documents.reject do |relative_path, _document|
  relative_path.end_with?("/config.yml") || relative_path.include?("/workflows/")
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

  if form.key?("title") && !form["title"].is_a?(String)
    errors << "Issue form #{relative_path} title must be a string"
  end

  if form.key?("type") && !form["type"].is_a?(String)
    errors << "Issue form #{relative_path} type must be a string"
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

    type = field["type"]
    unless ISSUE_FORM_FIELD_TYPES.include?(type)
      errors << "Issue form #{relative_path} body field #{field_number} has unsupported type #{type}"
    end

    if type != "markdown"
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

    required_attribute = type == "markdown" ? "value" : "label"
    attribute_value = attributes[required_attribute]
    unless attribute_value.is_a?(String) && !attribute_value.strip.empty?
      errors << "Issue form #{relative_path} body field #{field_number} #{type} needs a #{required_attribute}"
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

          normalized_option = option.strip
          if normalized_option.casecmp?("none")
            errors << "Issue form #{relative_path} body field #{field_number} dropdown uses reserved option none"
          end
          if seen_options[normalized_option]
            errors << "Issue form #{relative_path} body field #{field_number} dropdown repeats option #{normalized_option}"
          end
          seen_options[normalized_option] = true
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
    elsif validations.is_a?(Hash) &&
        validations.key?("required") &&
        ![true, false].include?(validations["required"])
      errors << "Issue form #{relative_path} body field #{field_number} required must be a boolean"
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
end

issue_template_config = yaml_documents[".github/ISSUE_TEMPLATE/config.yml"]

if issue_template_config.is_a?(Hash)
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

    %w[name about].each do |field|
      value = link[field]
      unless value.is_a?(String) && !value.strip.empty?
        errors << "Issue template contact link #{index + 1} needs #{field}"
      end
    end

    url = link["url"]
    valid_url = begin
      uri = URI.parse(url.to_s)
      url.is_a?(String) && uri.scheme == "https" && !uri.host.to_s.empty?
    rescue URI::InvalidURIError
      false
    end
    unless valid_url
      errors << "Issue template contact link #{index + 1} needs an HTTPS URL"
    end
  end
elsif ROOT.join(".github/ISSUE_TEMPLATE/config.yml").file?
  errors << "Issue template config must be a mapping"
end

markdown_files = ROOT.glob("**/*.md").reject do |path|
  path.each_filename.any? { |part| part == ".git" }
end.sort
markdown_link_count = 0

markdown_files.each do |path|
  relative_path = path.relative_path_from(ROOT).to_s

  path.read.scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |raw_target|
    target = raw_target.strip.sub(/\s+"[^"]*"\z/, "").delete_prefix("<").delete_suffix(">")
    next if target.empty? || target.start_with?("#")

    markdown_link_count += 1

    if target.match?(/\Ahttps?:\/\//)
      uri = URI.parse(target)
      errors << "External link lacks a host in #{relative_path}: #{target}" unless uri.host
      next
    end

    next if target.start_with?("mailto:")

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

    errors << "Broken relative link in #{relative_path}: #{target}" unless destination.exist?
  rescue URI::InvalidURIError
    errors << "Invalid link in #{relative_path}: #{target}"
  end
end

unless errors.empty?
  warn errors.join("\n")
  exit 1
end

puts "Validated #{yaml_files.length} YAML files and #{markdown_link_count} Markdown links."
