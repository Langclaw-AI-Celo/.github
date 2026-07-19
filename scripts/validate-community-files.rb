# frozen_string_literal: true

require "pathname"
require "uri"
require "yaml"

ROOT = Pathname(__dir__).join("..").expand_path
REQUIRED_FILES = %w[
  CODE_OF_CONDUCT.md
  CONTRIBUTING.md
  README.md
  SECURITY.md
  SUPPORT.md
  .github/pull_request_template.md
  profile/README.md
].freeze

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

  %w[name description].each do |field|
    value = form[field]
    errors << "Issue form #{relative_path} needs #{field}" unless value.is_a?(String) && !value.strip.empty?
  end

  body = form["body"]
  unless body.is_a?(Array) && !body.empty?
    errors << "Issue form #{relative_path} needs a non-empty body"
    next
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
