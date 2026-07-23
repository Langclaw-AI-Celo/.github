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
PUBLIC_IDENTIFIER_FILES = %w[README.md profile/README.md].freeze
PUBLIC_IDENTIFIER_LABELS = [
  "`LangclawRegistry`",
  "`LangclawTradingJournal`",
  "`LangclawUsageVault`",
  "Celo USDT deposit token",
  "ERC-8004 identity registry",
  "Agent owner / recorder"
].freeze
ISSUE_FORM_PROJECT_PATTERN = /\A[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\/[1-9]\d*\z/
ISSUE_FORM_FORBIDDEN_LABEL_PATTERN = /\bpasswords?\b/i
HTML_ANCHOR_HREF_PATTERN = /
  \A<a\b
  (?:
    \s+
    (?!href\b)
    [^\s"'=<>`\/]+
    (?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?
  )*
  \s+href\s*=\s*
  (?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))
/ix
BARE_MARKDOWN_URL_PATTERN = %r{
  (?<![A-Za-z0-9])
  https?://
  [^\s<>"'`]+
}ix
MARKDOWN_HTML_BLOCK_TAG_PATTERN = %r{
  \A[ \t]{0,3}</?(?:
    address|article|aside|base|basefont|blockquote|body|caption|center|col|
    colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|
    footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|
    li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|
    search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul
  )(?:[ \t]+|/?>|(?:\r?\n)?\z)
}ix
MARKDOWN_HTML_COMPLETE_TAG_PATTERN = %r{
  \A[ \t]{0,3}(?:
    </[A-Za-z][A-Za-z0-9-]*[ \t]*>
    |
    <[A-Za-z][A-Za-z0-9-]*
    (?:
      [ \t]+[^\s<>"'=]+
      (?:[ \t]*=[ \t]*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?
    )*
    [ \t]*/?>
  )[ \t]*(?:\r?\n)?\z
}x

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

def html_tag_tokens(contents)
  tags = []
  tag = nil
  quote = nil

  contents.each_char do |character|
    if tag.nil?
      tag = String.new("<") if character == "<"
      next
    end

    if quote.nil? && character == "<"
      tag = String.new("<")
      next
    end

    if tag == "<" && !character.match?(/[A-Za-z]/)
      tag = nil
      next
    end

    tag << character

    if quote
      quote = nil if character == quote
    elsif character == '"' || character == "'"
      quote = character
    elsif character == ">"
      tags << tag
      tag = nil
    end
  end

  tags
end

def html_anchor_targets(contents)
  html_tag_tokens(contents).each_with_object([]) do |tag, targets|
    match = tag.match(HTML_ANCHOR_HREF_PATTERN)
    targets << match.captures.compact.first if match
  end
end

def mask_markdown_text(value)
  value.gsub(/[^\r\n]/, " ")
end

def markdown_blockquote_line(line)
  depth = 0
  remainder = line

  loop do
    prefix = remainder.match(/\A[ \t]{0,3}>[ \t]?/)
    break unless prefix

    depth += 1
    remainder = remainder[prefix[0].length..-1] || ""
  end

  [depth, remainder]
end

def markdown_indent_width(value)
  column = 0

  value.each_char do |character|
    column = if character == "\t"
      column + (4 - (column % 4))
    else
      column + 1
    end
  end

  column
end

def strip_markdown_indent(line, required_width)
  column = 0

  line.each_char.with_index do |character, index|
    break unless character == " " || character == "\t"

    column = if character == "\t"
      column + (4 - (column % 4))
    else
      column + 1
    end

    return line[(index + 1)..-1] || "" if column >= required_width
  end

  nil
end

def markdown_list_item_content(line)
  remainder = line
  can_interrupt = nil
  indented_code = false
  list_indent = 0
  list_item = false

  loop do
    marker = remainder.match(
      /\A([ \t]{0,3})((?:[-+*])|(\d{1,9})[.)])([ \t]+)/
    )
    break unless marker

    can_interrupt = marker[3].nil? || marker[3].to_i == 1 if can_interrupt.nil?
    indented_code ||= markdown_indent_width(marker[4]) >= 5
    list_item = true
    list_indent += markdown_indent_width(marker[0])
    remainder = remainder[marker[0].length..-1] || ""
  end

  {
    can_interrupt: can_interrupt,
    content: remainder,
    indent: list_indent,
    indented_code: indented_code,
    list_item: list_item,
  }
end

def markdown_fence_opening(line)
  list_item = markdown_list_item_content(line)
  return if list_item[:indented_code]

  remainder = list_item[:content]

  opening = remainder.match(/\A[ \t]{0,3}(`{3,}|~{3,})([^\r\n]*)/)
  return unless opening

  marker = opening[1]
  info = opening[2]
  return if marker.start_with?("`") && info.include?("`")

  {
    character: marker[0],
    length: marker.length,
    list_indent: list_item[:indent],
  }
end

def markdown_html_block_opening(line, paragraph_open)
  type_one = line.match(
    /\A[ \t]{0,3}<(script|pre|style|textarea)(?:[ \t]+|>|(?:\r?\n)?\z)/i
  )
  if type_one
    return {
      end_pattern: %r{</#{Regexp.escape(type_one[1])}[ \t]*>}i,
      ends_on_blank: false,
    }
  end

  return { end_pattern: /-->/, ends_on_blank: false } if line.match?(
    /\A[ \t]{0,3}<!--/
  )
  return { end_pattern: /\?>/, ends_on_blank: false } if line.match?(
    /\A[ \t]{0,3}<\?/
  )
  return { end_pattern: />/, ends_on_blank: false } if line.match?(
    /\A[ \t]{0,3}<![A-Z]/
  )
  return { end_pattern: /\]\]>/, ends_on_blank: false } if line.match?(
    /\A[ \t]{0,3}<!\[CDATA\[/
  )
  return { end_pattern: nil, ends_on_blank: true } if line.match?(
    MARKDOWN_HTML_BLOCK_TAG_PATTERN
  )
  return if paragraph_open
  return unless line.match?(MARKDOWN_HTML_COMPLETE_TAG_PATTERN)

  { end_pattern: nil, ends_on_blank: true }
end

def markdown_structural_line?(line)
  return true if line.match?(/\A[ \t]{0,3}\#{1,6}(?:[ \t]+|\r?\n?\z)/)
  return true if line.match?(
    /\A[ \t]{0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})(?:\r?\n)?\z/
  )
  return true if line.match?(/\A[ \t]{0,3}(?:=+|-+)[ \t]*(?:\r?\n)?\z/)

  false
end

def markdown_table_delimiter_line?(line)
  return false unless line.include?("|")

  value = line.strip
  value = value[1..-1] if value.start_with?("|")
  value = value[0...-1] if value.end_with?("|")
  cells = value.split("|", -1)

  !cells.empty? && cells.all? do |cell|
    cell.match?(/\A[ \t]*:?-{3,}:?[ \t]*\z/)
  end
end

def markdown_table_row_line?(line)
  line.each_char.with_index.any? do |character, index|
    character == "|" && !markdown_character_escaped?(line, index)
  end
end

def mask_markdown_blocks(contents, mask_html: true)
  fence = nil
  html_block = nil
  paragraph_quote_depth = nil
  table = false

  contents.each_line.map do |line|
    quote_depth, markdown_line = markdown_blockquote_line(line)

    if fence
      fence = nil if quote_depth < fence[:quote_depth]

      fence_line = markdown_line
      if fence && fence[:list_indent].positive? && !fence_line.strip.empty?
        fence_line = strip_markdown_indent(fence_line, fence[:list_indent])
        fence = nil unless fence_line
      end

      if fence
        closing_fence = %r{
          \A[ \t]{0,3}
          #{Regexp.escape(fence[:character])}{#{fence[:length]},}
          [ \t]*(?:\r?\n)?\z
        }x
        fence = nil if fence_line.match?(closing_fence)
        paragraph_quote_depth = nil
        next mask_markdown_text(line)
      end
    end

    if html_block
      html_block = nil if quote_depth < html_block[:quote_depth]

      html_line = markdown_line
      if html_block && html_block[:list_indent].positive? && !html_line.strip.empty?
        html_line = strip_markdown_indent(html_line, html_block[:list_indent])
        html_block = nil unless html_line
      end

      if html_block
        if html_block[:ends_on_blank] && html_line.strip.empty?
          html_block = nil
        else
          if html_block[:end_pattern] && html_line.match?(html_block[:end_pattern])
            html_block = nil
          end
          paragraph_quote_depth = nil
          next mask_html ? mask_markdown_text(line) : line
        end
      end
    end

    if table
      if !markdown_line.strip.empty? && markdown_table_row_line?(markdown_line)
        paragraph_quote_depth = nil
        next line
      end

      table = false
    end

    opening = markdown_fence_opening(markdown_line)
    if opening
      fence = opening.merge(quote_depth: quote_depth)
      paragraph_quote_depth = nil
      next mask_markdown_text(line)
    end

    list_item = markdown_list_item_content(markdown_line)
    if list_item[:indented_code]
      paragraph_quote_depth = nil
      next mask_markdown_text(line)
    end

    html_line = list_item[:content]
    paragraph_open = paragraph_quote_depth == quote_depth && !list_item[:list_item]
    html_opening = markdown_html_block_opening(html_line, paragraph_open)
    if html_opening
      html_block = html_opening.merge(
        list_indent: list_item[:indent],
        quote_depth: quote_depth,
      )
      if html_block[:end_pattern] && html_line.match?(html_block[:end_pattern])
        html_block = nil
      end
      paragraph_quote_depth = nil
      next mask_html ? mask_markdown_text(line) : line
    end

    if markdown_line.strip.empty?
      paragraph_quote_depth = nil
      next line
    end

    if paragraph_quote_depth == quote_depth && markdown_table_delimiter_line?(
      markdown_line
    )
      table = true
      paragraph_quote_depth = nil
      next line
    end

    paragraph_quote_depth = nil if paragraph_quote_depth != quote_depth

    if markdown_line.match?(/\A(?: {4}|\t)/)
      unless paragraph_quote_depth == quote_depth
        paragraph_quote_depth = nil
        next mask_markdown_text(line)
      end
    end

    paragraph_quote_depth = if markdown_structural_line?(list_item[:content])
      nil
    else
      quote_depth
    end
    line
  end.join
end

def markdown_character_escaped?(value, index)
  backslashes = 0
  cursor = index - 1

  while cursor >= 0 && value[cursor] == "\\"
    backslashes += 1
    cursor -= 1
  end

  backslashes.odd?
end

def markdown_backtick_run(value, start_index, respect_escape: true)
  index = start_index

  while index < value.length
    unless value[index] == "`" && (
      !respect_escape || !markdown_character_escaped?(value, index)
    )
      index += 1
      next
    end

    finish = index
    finish += 1 while finish < value.length && value[finish] == "`"
    return [index, finish - index]
  end

  nil
end

def mask_markdown_code_spans_in_block(block)
  masked = block.dup
  cursor = 0

  while (opening = markdown_backtick_run(block, cursor))
    opening_index, opening_length = opening
    search_index = opening_index + opening_length
    closing = nil

    while (candidate = markdown_backtick_run(
      block,
      search_index,
      respect_escape: false
    ))
      candidate_index, candidate_length = candidate
      if candidate_length == opening_length
        closing = candidate
        break
      end

      search_index = candidate_index + candidate_length
    end

    unless closing
      cursor = opening_index + opening_length
      next
    end

    closing_index, closing_length = closing
    span_length = closing_index + closing_length - opening_index
    masked[opening_index, span_length] = mask_markdown_text(
      block[opening_index, span_length]
    )
    cursor = closing_index + closing_length
  end

  masked
end

def mask_markdown_inline_block(block, mask_html: true)
  masked = mask_markdown_code_spans_in_block(block)
  masked = masked
    .gsub(/<!--.*?-->/m) { |match| mask_markdown_text(match) }
    .sub(/<!--.*\z/m) { |match| mask_markdown_text(match) }

  return masked unless mask_html

  masked
    .gsub(/<a\b[^>]*>.*?<\/a\s*>/im) { |match| mask_markdown_text(match) }
    .gsub(/<(code|pre)\b[^>]*>.*?<\/\1\s*>/im) do |match|
      mask_markdown_text(match)
    end
end

def mask_markdown_table_row(line, mask_html: true)
  output = []
  cell_start = 0

  line.each_char.with_index do |character, index|
    next unless character == "|" && !markdown_character_escaped?(line, index)

    output << mask_markdown_inline_block(
      line[cell_start...index],
      mask_html: mask_html,
    )
    output << "|"
    cell_start = index + 1
  end

  output << mask_markdown_inline_block(
    line[cell_start..-1] || "",
    mask_html: mask_html,
  )
  output.join
end

def mask_markdown_inline_content(contents, mask_html: true)
  output = []
  block = []
  block_quote_depth = nil
  table = false

  flush = lambda do
    unless block.empty?
      output << mask_markdown_inline_block(block.join, mask_html: mask_html)
      block.clear
    end
    block_quote_depth = nil
  end

  contents.each_line do |line|
    quote_depth, markdown_line = markdown_blockquote_line(line)
    list_item = markdown_list_item_content(markdown_line)
    content_line = list_item[:content]

    if markdown_line.strip.empty?
      flush.call
      output << line
      table = false
      next
    end

    if table
      if markdown_table_row_line?(markdown_line)
        flush.call
        output << mask_markdown_table_row(line, mask_html: mask_html)
        next
      end

      table = false
    end

    if !block.empty? && markdown_table_delimiter_line?(markdown_line)
      header = block.pop
      flush.call
      output << mask_markdown_table_row(header, mask_html: mask_html) if header
      output << line
      table = true
      next
    end

    if block_quote_depth && quote_depth > block_quote_depth
      flush.call
    end

    if list_item[:list_item] && (
      block.empty? || list_item[:can_interrupt]
    )
      flush.call
    end

    if content_line.match?(/\A[ \t]{0,3}\#{1,6}(?:[ \t]+|\r?\n?\z)/)
      flush.call
      output << mask_markdown_inline_block(line, mask_html: mask_html)
      next
    end

    if markdown_structural_line?(content_line)
      block << line
      flush.call
      next
    end

    block_quote_depth = quote_depth
    block << line
  end

  flush.call
  output.join
end

def mask_nonrendered_markdown(contents, mask_html: true)
  visible_contents = mask_markdown_blocks(contents, mask_html: mask_html)
  mask_markdown_inline_content(visible_contents, mask_html: mask_html)
end

def bare_markdown_url_targets(contents)
  visible_contents = mask_nonrendered_markdown(contents)

  visible_contents.each_line.flat_map do |line|
    next [] if line.match?(/\A[ \t]{0,3}\[(?!\^)[^\]\n]+\]:/)

    rendered_text = line
      .gsub(/!?\[[^\]\n]*\]\([^\)\n]*\)/, " ")
      .gsub(/\[[^\]\n]+\]\[[^\]\n]*\]/, " ")
      .gsub(/<[^>\n]*>/, " ")

    rendered_text.scan(BARE_MARKDOWN_URL_PATTERN)
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

def markdown_table_values(contents, label)
  visible_contents = mask_markdown_blocks(contents)

  visible_contents.each_line.each_with_object([]) do |line, values|
    columns = line.strip.split("|", -1).map(&:strip)
    values << columns[2] if columns.length >= 4 && columns[1] == label
  end
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

PUBLIC_IDENTIFIER_LABELS.each do |label|
  displayed_label = label.delete("`")
  values_by_file = {}

  PUBLIC_IDENTIFIER_FILES.each do |relative_path|
    path = ROOT.join(relative_path)
    next unless path.file? && path_inside_repository?(path)

    values = markdown_table_values(path.read, label)
    if values.length != 1
      errors << "Public identifier #{displayed_label} must appear exactly once in #{relative_path}"
      next
    end

    values_by_file[relative_path] = values.first
  end

  next unless values_by_file.length == PUBLIC_IDENTIFIER_FILES.length
  next if values_by_file.values.uniq.length == 1

  errors << "Public identifier #{displayed_label} differs between #{PUBLIC_IDENTIFIER_FILES.join(" and ")}"
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
        attribute_value.unicode_normalize(:nfkc).match?(ISSUE_FORM_FORBIDDEN_LABEL_PATTERN)
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
    references.select { |reference| reference.is_a?(String) && !reference.empty? }
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

  seen_contact_link_names = {}
  seen_contact_link_urls = {}

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

    name = link["name"]
    if name.is_a?(String) && !name.strip.empty?
      displayed_name = name.strip
      normalized_name = displayed_name.unicode_normalize(:nfkc).downcase
      if seen_contact_link_names[normalized_name]
        errors << "Issue template contact link #{index + 1} repeats name #{displayed_name}"
      end
      seen_contact_link_names[normalized_name] = true
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
      if seen_contact_link_urls[url]
        errors << "Issue template contact link #{index + 1} repeats URL #{url}"
      end
      seen_contact_link_urls[url] = true
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
  visible_markdown = mask_nonrendered_markdown(contents)
  visible_html = mask_nonrendered_markdown(contents, mask_html: false)
  inline_targets = visible_markdown.scan(/\[[^\]]*\]\(([^)]*)\)/).flatten
  autolink_targets = visible_markdown.scan(
    /(?<!\]\()<((?:https?|mailto):[^<>\r\n]*)>/i
  ).flatten
  html_targets = html_anchor_targets(visible_html)
  bare_url_targets = bare_markdown_url_targets(contents)
  reference_definitions = visible_markdown.scan(
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
  visible_markdown.scan(/\[([^\]\n]+)\]\[([^\]\n]*)\]/).each do |text, label|
    reference = label.empty? ? text : label
    next if defined_references.include?(normalize_reference.call(reference))

    errors << "Undefined Markdown link reference in #{relative_path}: #{reference}"
  end

  (inline_targets + autolink_targets + html_targets + reference_targets + bare_url_targets).each do |raw_target|
    target = raw_target.strip.sub(/\s+"[^"]*"\z/, "").delete_prefix("<").delete_suffix(">")
    if target.empty?
      errors << "Empty Markdown link target in #{relative_path}"
      next
    end
    next if target.start_with?("#")

    markdown_link_count += 1

    if target.match?(/\Ahttps?:\/\//i)
      uri = URI.parse(target)
      errors << "External link lacks a host in #{relative_path}: #{target}" unless uri.host
      unless uri.scheme.to_s.casecmp?("https")
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
    if file_target.include?("\0")
      errors << "Invalid link in #{relative_path}: #{target}"
      next
    end

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
