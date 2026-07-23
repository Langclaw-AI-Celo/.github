# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"

REPOSITORY_ROOT = Pathname(__dir__).join("..").expand_path
VALIDATOR = REPOSITORY_ROOT.join("scripts/validate-community-files.rb")

class CommunityFilesValidatorTest < Minitest::Test
  def test_rejects_missing_public_identifier
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      profile_path = root.join("profile/README.md")
      profile_path.write(
        profile_path.read.each_line.reject do |line|
          line.start_with?("| `LangclawTradingJournal` |")
        end.join
      )

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr,
        "Public identifier LangclawTradingJournal must appear exactly once in profile/README.md"
    end
  end

  def test_rejects_duplicate_public_identifier
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      readme_path = root.join("README.md")
      identifier_row = "| `LangclawRegistry` | `0xe69755e4249c4978c39fbe847ca9674ce7af3505` |"
      readme_path.write(readme_path.read.sub(identifier_row, "#{identifier_row}\n#{identifier_row}"))

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Public identifier LangclawRegistry must appear exactly once in README.md"
    end
  end

  def test_rejects_conflicting_public_identifier_values
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      profile_path = root.join("profile/README.md")
      profile_path.write(
        profile_path.read.sub(
          "0xe69755e4249c4978c39fbe847ca9674ce7af3505",
          "0x1111111111111111111111111111111111111111"
        )
      )

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Public identifier LangclawRegistry differs between README.md and profile/README.md"
    end
  end

  def test_ignores_public_identifier_rows_in_code_examples
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      readme_path = root.join("README.md")
      readme_path.write(<<~MARKDOWN)
        #{readme_path.read}

        ```markdown
        | `LangclawRegistry` | `0x1111111111111111111111111111111111111111` |
        ```
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_rejects_invalid_issue_template_config
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/config.yml").write(<<~YAML)
        blank_issues_enabled: "false"
        contact_links:
          - name: ""
            url: javascript:alert(1)
            about: ""
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "blank_issues_enabled must be a boolean"
      assert_includes stderr, "contact link 1 needs name"
      assert_includes stderr, "contact link 1 needs about"
      assert_includes stderr, "contact link 1 needs an HTTPS URL"
    end
  end

  def test_rejects_invalid_issue_form_fields
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - invalid
          - type: input
            id: invalid id
            attributes: []
          - type: chart
            id: chart
            attributes:
              label: Chart
          - type: markdown
            attributes: {}
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "body field 1 must be a mapping"
      assert_includes stderr, "body field 2 has invalid id invalid id"
      assert_includes stderr, "body field 2 attributes must be a mapping"
      assert_includes stderr, "body field 3 has unsupported type chart"
      assert_includes stderr, "body field 4 markdown needs a value"
    end
  end

  def test_rejects_non_string_issue_form_ids_without_crashing
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: input
            id: 7
            attributes:
              label: Reproduction
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "body field 1 has invalid id 7"
      refute_includes stderr, "NoMethodError"
    end
  end

  def test_rejects_invalid_issue_form_options
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/feature_request.yml").write(<<~YAML)
        name: Feature request
        description: Propose a focused improvement.
        body:
          - type: dropdown
            id: repository
            attributes:
              label: Repository
              options:
                - true
                - none
                - frontend
                - frontend
          - type: checkboxes
            id: checks
            attributes:
              label: Checks
              options:
                - invalid
                - label: ""
                  required: "true"
                - label: Accept
                - label: Accept
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "body field 1 dropdown option 1 must be a non-empty string"
      assert_includes stderr, "body field 1 dropdown uses reserved option none"
      assert_includes stderr, "body field 1 dropdown repeats option frontend"
      assert_includes stderr, "body field 2 checkbox option 1 must be a mapping"
      assert_includes stderr, "body field 2 checkbox option 2 needs label"
      assert_includes stderr, "body field 2 checkbox option 2 required must be a boolean"
      assert_includes stderr, "body field 2 checkbox repeats label Accept"
    end
  end

  def test_rejects_case_and_unicode_equivalent_dropdown_options
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      form_path = root.join(".github/ISSUE_TEMPLATE/bug_report.yml")
      form_path.write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: dropdown
            id: network
            attributes:
              label: Network
              default: 0
              options:
                - " Celo "
                - celo
                - ＣＥＬＯ
                - Ｎ／Ａ
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "bug_report.yml body field 1 dropdown repeats option celo"
      assert_includes stderr, "bug_report.yml body field 1 dropdown repeats option ＣＥＬＯ"
      assert_includes stderr, "bug_report.yml body field 1 dropdown uses reserved option n/a"

      form_path.write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: dropdown
            id: network
            attributes:
              label: Network
              options:
                - Celo
                - Celo!
                - Celo Mainnet
                - Celo  Mainnet
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_rejects_non_boolean_dropdown_multiple
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: dropdown
            id: repository
            attributes:
              label: Repository
              multiple: "true"
              options:
                - frontend
                - backend
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "body field 1 dropdown multiple must be a boolean"
    end
  end

  def test_rejects_markdown_only_forms_and_invalid_required_flags
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: markdown
            attributes:
              value: Add a real response field.
      YAML
      root.join(".github/ISSUE_TEMPLATE/feature_request.yml").write(<<~YAML)
        name: Feature request
        description: Propose a focused improvement.
        body:
          - type: input
            id: proposal
            attributes:
              label: Proposal
            validations:
              required: "true"
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "bug_report.yml needs at least one response field"
      assert_includes stderr, "feature_request.yml body field 1 required must be a boolean"
    end
  end

  def test_rejects_non_string_issue_form_title
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        title:
          - Bug
        body:
          - type: input
            id: reproduction
            attributes:
              label: Reproduction
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "bug_report.yml title must be a string"
    end
  end

  def test_rejects_non_string_issue_form_type
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        type:
          - Bug
        body:
          - type: input
            id: reproduction
            attributes:
              label: Reproduction
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "bug_report.yml type must be a string"
    end
  end

  def test_rejects_empty_optional_issue_form_metadata
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        title: "   "
        type: ""
        body:
          - type: input
            id: reproduction
            attributes:
              label: Reproduction
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "bug_report.yml title must be a non-empty string"
      assert_includes stderr, "bug_report.yml type must be a non-empty string"
    end
  end

  def test_validates_issue_form_assignment_metadata
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      form_path = root.join(".github/ISSUE_TEMPLATE/bug_report.yml")
      form_path.write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        labels: bug, triage
        assignees:
          - Nant361
        body:
          - type: input
            id: reproduction
            attributes:
              label: Reproduction
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr

      form_path.write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        labels:
          invalid: mapping
        assignees:
          - Nant361
          - false
        body:
          - type: input
            id: reproduction
            attributes:
              label: Reproduction
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "bug_report.yml labels must be a string or list of non-empty strings"
      assert_includes stderr, "bug_report.yml assignees must be a string or list of non-empty strings"
    end
  end

  def test_validates_issue_form_project_metadata
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      form_path = root.join(".github/ISSUE_TEMPLATE/bug_report.yml")
      form_path.write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        projects: Langclaw-AI-Celo/1, Nant361/42
        body:
          - type: input
            id: reproduction
            attributes:
              label: Reproduction
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr

      form_path.write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        projects:
          - Langclaw-AI-Celo/not-a-number
          - invalid
          - false
        body:
          - type: input
            id: reproduction
            attributes:
              label: Reproduction
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "bug_report.yml projects must use PROJECT-OWNER/PROJECT-NUMBER values"
    end
  end

  def test_rejects_unpermitted_issue_form_top_level_keys
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        unexpected: value
        body:
          - type: input
            id: reproduction
            attributes:
              label: Reproduction
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "bug_report.yml has unpermitted top-level key unexpected"
    end
  end

  def test_rejects_unpermitted_issue_form_body_keys
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: input
            id: reproduction
            unexpected: value
            attributes:
              label: Reproduction
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "body field 1 has unpermitted key unexpected"
    end
  end

  def test_rejects_unpermitted_issue_form_attributes
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: input
            id: reproduction
            attributes:
              label: Reproduction
              multiple: true
          - type: markdown
            attributes:
              value: Context
              placeholder: Not supported
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "body field 1 input has unpermitted attribute multiple"
      assert_includes stderr, "body field 2 markdown has unpermitted attribute placeholder"
    end
  end

  def test_rejects_unpermitted_issue_form_validations
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: input
            id: reproduction
            attributes:
              label: Reproduction
            validations:
              accept: .txt
          - type: markdown
            attributes:
              value: Context
            validations:
              required: true
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "body field 1 input has unpermitted validation accept"
      assert_includes stderr, "body field 2 markdown has unpermitted validation required"
    end
  end

  def test_rejects_ids_on_markdown_fields
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: markdown
            id: context
            attributes:
              value: Context
          - type: input
            id: reproduction
            attributes:
              label: Reproduction
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "body field 1 markdown cannot define an id"
    end
  end

  def test_rejects_unpermitted_checkbox_option_keys
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: checkboxes
            id: confirmation
            attributes:
              label: Confirmation
              options:
                - label: I confirm this report is complete.
                  checked: true
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "checkbox option 1 has unpermitted key checked"
    end
  end

  def test_rejects_invalid_optional_text_attributes
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: input
            id: reproduction
            attributes:
              label: Reproduction
              description: false
              placeholder: ""
              value:
                - invalid
          - type: textarea
            id: logs
            attributes:
              label: Logs
              render: 123
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "body field 1 input description must be a non-empty string"
      assert_includes stderr, "body field 1 input placeholder must be a non-empty string"
      assert_includes stderr, "body field 1 input value must be a non-empty string"
      assert_includes stderr, "body field 2 textarea render must be a non-empty string"
    end
  end

  def test_rejects_invalid_dropdown_defaults
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: dropdown
            id: repository
            attributes:
              label: Repository
              options:
                - frontend
                - backend
              default: "0"
          - type: dropdown
            id: priority
            attributes:
              label: Priority
              options:
                - P0
                - P1
              default: 2
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "body field 1 dropdown default must index an option"
      assert_includes stderr, "body field 2 dropdown default must index an option"
    end
  end

  def test_rejects_reserved_dropdown_options_with_defaults
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: dropdown
            id: repository
            attributes:
              label: Repository
              options:
                - frontend
                - n/a
              default: 0
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "body field 1 dropdown uses reserved option n/a"
    end
  end

  def test_rejects_invalid_upload_accept_lists
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: upload
            id: screenshots
            attributes:
              label: Screenshots
            validations:
              accept:
                - .png
          - type: upload
            id: attachment
            attributes:
              label: Attachment
            validations:
              accept: ".pdf,.exe"
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "body field 1 upload accept must be a comma-separated extension list"
      assert_includes stderr, "body field 2 upload accept contains unsupported extension .exe"
    end
  end

  def test_rejects_unpermitted_issue_template_config_keys
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/config.yml").write(<<~YAML)
        blank_issues_enabled: false
        contact_links: []
        unexpected: value
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Issue template config has unpermitted key unexpected"
    end
  end

  def test_rejects_unpermitted_contact_link_keys
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/config.yml").write(<<~YAML)
        blank_issues_enabled: false
        contact_links:
          - name: Support
            url: https://github.com/Langclaw-AI-Celo/.github/discussions
            about: Ask a support question.
            icon: comment
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Issue template contact link 1 has unpermitted key icon"
    end
  end

  def test_rejects_duplicate_contact_link_names_and_urls
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/config.yml").write(<<~YAML)
        blank_issues_enabled: false
        contact_links:
          - name: Support
            url: https://github.com/Langclaw-AI-Celo/.github/discussions
            about: Ask a support question.
          - name: ＳＵＰＰＯＲＴ
            url: https://github.com/Langclaw-AI-Celo/.github/blob/main/SUPPORT.md
            about: Read the support policy.
          - name: Documentation
            url: https://github.com/Langclaw-AI-Celo/.github/discussions
            about: Browse common answers.
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Issue template contact link 2 repeats name ＳＵＰＰＯＲＴ"
      assert_includes stderr,
        "Issue template contact link 3 repeats URL https://github.com/Langclaw-AI-Celo/.github/discussions"
    end
  end

  def test_allows_omitted_issue_form_ids
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: input
            attributes:
              label: Reproduction
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_ignores_non_template_github_yaml
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/dependabot.yml").write(<<~YAML)
        version: 2
        updates:
          - package-ecosystem: github-actions
            directory: /
            schedule:
              interval: weekly
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_rejects_issue_form_names_with_three_characters
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug
        description: Report a reproducible problem.
        body:
          - type: textarea
            attributes:
              label: Reproduction steps
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "bug_report.yml name must contain more than 3 characters"
    end
  end

  def test_rejects_yaml_extension_for_issue_forms
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yaml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: textarea
            attributes:
              label: Reproduction steps
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Issue form .github/ISSUE_TEMPLATE/bug_report.yaml must use the .yml extension"
    end
  end

  def test_rejects_password_labels_on_text_fields
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: input
            attributes:
              label: Account password
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "body field 1 input label contains forbidden word password"
    end
  end

  def test_rejects_unicode_equivalent_password_labels_on_text_fields
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: input
            attributes:
              label: Account Ｐａｓｓｗｏｒｄ
          - type: textarea
            attributes:
              label: 𝙿𝚊𝚜𝚜𝚠𝚘𝚛𝚍𝚜 recovery notes
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "body field 1 input label contains forbidden word password"
      assert_includes stderr, "body field 2 textarea label contains forbidden word password"

      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: input
            attributes:
              label: Celo 钱包 address
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_rejects_colliding_issue_form_references
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: Bug report
        description: Report a reproducible problem.
        body:
          - type: input
            attributes:
              label: Name?
          - type: input
            id: name
            attributes:
              label: Name???????
          - type: textarea
            attributes:
              label: Wallet
          - type: checkboxes
            id: confirmations
            attributes:
              label: Confirmation
              options:
                - label: Wallet
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "bug_report.yml repeats field reference name"
      assert_includes stderr, "bug_report.yml repeats field reference wallet"
    end
  end

  def test_rejects_relative_links_outside_repository
    Dir.mktmpdir("community-files") do |directory|
      container = Pathname(directory)
      root = container.join("repository")
      root.mkpath
      copy_profile_files(root)
      container.join("outside.md").write("Outside the repository.\n")
      root.join("README.md").write("[Outside](../outside.md)\n")

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Relative link escapes repository in README.md: ../outside.md"
    end
  end

  def test_reports_percent_encoded_null_bytes_as_invalid_links
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write("[Invalid target](%00)\n")

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Invalid link in README.md: %00"
      refute_includes stderr, "ArgumentError"
      refute_includes stderr, "pathname contains null byte"
    end
  end

  def test_rejects_duplicate_yaml_mapping_keys
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: First bug report
        name: Replacement bug report
        description: Report a reproducible problem.
        body:
          - type: input
            id: reproduction
            attributes:
              label: Reproduction
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Duplicate YAML key name in .github/ISSUE_TEMPLATE/bug_report.yml"
    end
  end

  def test_rejects_duplicate_issue_form_names
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      %w[bug_report.yml feature_request.yml].each do |filename|
        root.join(".github/ISSUE_TEMPLATE", filename).write(<<~YAML)
          name: Duplicate template
          description: Collect focused input.
          body:
            - type: input
              id: response
              attributes:
                label: Response
        YAML
      end

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Issue template name Duplicate template is repeated"
    end
  end

  def test_rejects_repository_files_and_links_resolving_through_external_symlinks
    Dir.mktmpdir("community-files") do |directory|
      container = Pathname(directory)
      root = container.join("repository")
      root.mkpath
      copy_profile_files(root)

      outside_readme = container.join("outside-readme.md")
      outside_readme.write("External readme.\n")
      FileUtils.rm(root.join("README.md"))
      File.symlink(outside_readme, root.join("README.md"))

      outside_form = container.join("outside-form.yml")
      outside_form.write(<<~YAML)
        name: External form
        description: This file lives outside the repository.
        body:
          - type: input
            attributes:
              label: Response
      YAML
      FileUtils.rm(root.join(".github/ISSUE_TEMPLATE/bug_report.yml"))
      File.symlink(outside_form, root.join(".github/ISSUE_TEMPLATE/bug_report.yml"))

      outside_target = container.join("outside-target.md")
      outside_target.write("External target.\n")
      File.symlink(outside_target, root.join("profile/linked.md"))
      root.join("profile/README.md").write("[External](linked.md)\n")

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Required file resolves outside repository: README.md"
      assert_includes stderr, "YAML file resolves outside repository: .github/ISSUE_TEMPLATE/bug_report.yml"
      assert_includes stderr, "Relative link escapes repository in profile/README.md: linked.md"
    end
  end

  def test_rejects_userinfo_in_public_urls
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      misleading_url = "https://github.com@evil.example/support"
      root.join("README.md").write("[Misleading support](#{misleading_url})\n")
      root.join(".github/ISSUE_TEMPLATE/config.yml").write(<<~YAML)
        blank_issues_enabled: false
        contact_links:
          - name: Misleading support
            url: #{misleading_url}
            about: This host is not GitHub.
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Issue template contact link 1 URL must not include user information"
      assert_includes stderr, "External link includes user information in README.md: #{misleading_url}"
    end
  end

  def test_rejects_out_of_range_ports_in_public_urls
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      invalid_url = "https://example.com:99999/support"
      write_readme_fixture(
        root,
        "[Invalid port](#{invalid_url})"
      )
      root.join(".github/ISSUE_TEMPLATE/config.yml").write(<<~YAML)
        blank_issues_enabled: false
        contact_links:
          - name: Invalid port
            url: #{invalid_url}
            about: This port is outside the valid network range.
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr,
        "Issue template contact link 1 needs an HTTPS URL"
      assert_includes stderr,
        "External link has an invalid port in README.md: #{invalid_url}"

      valid_url = "https://example.com:65535/support"
      root.join("README.md").write(
        root.join("README.md").read.sub(invalid_url, valid_url)
      )
      config_path = root.join(".github/ISSUE_TEMPLATE/config.yml")
      config_path.write(config_path.read.sub(invalid_url, valid_url))

      _stdout, valid_stderr, valid_status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert valid_status.success?, valid_stderr
    end
  end

  def test_rejects_multiple_yaml_documents
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/bug_report.yml").write(<<~YAML)
        name: First document
        description: This document is valid by itself.
        body:
          - type: input
            attributes:
              label: Response
        ---
        name: Ignored document
        description: Psych safe_load ignores this document.
        body:
          - type: input
            attributes:
              label: Ignored response
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "YAML file must contain exactly one document: .github/ISSUE_TEMPLATE/bug_report.yml"
    end
  end

  def test_rejects_names_shared_by_yaml_and_markdown_issue_templates
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/classic.md").write(<<~MARKDOWN)
        ---
        name: Bug report
        about: Report a bug with the classic template.
        title: "[Classic bug]: "
        labels: bug
        assignees: ""
        ---

        Describe the bug.
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Issue template name Bug report is repeated"
    end
  end

  def test_rejects_duplicate_keys_in_classic_template_front_matter
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/classic.md").write(<<~MARKDOWN)
        ---
        name: Bug report
        name: Unique replacement
        about: Report a bug with the classic template.
        ---

        Describe the bug.
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Duplicate YAML front matter key name in .github/ISSUE_TEMPLATE/classic.md"
    end
  end

  def test_rejects_classic_issue_templates_without_about_metadata
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/classic.md").write(<<~MARKDOWN)
        ---
        name: Classic report
        ---

        Describe the report.
      MARKDOWN
      root.join(".github/ISSUE_TEMPLATE/plain.md").write("Describe the report.\n")

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Classic issue template .github/ISSUE_TEMPLATE/classic.md needs about"
      assert_includes stderr, "Classic issue template .github/ISSUE_TEMPLATE/plain.md needs YAML front matter"
    end
  end

  def test_rejects_invalid_classic_issue_template_metadata
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/ISSUE_TEMPLATE/classic.md").write(<<~MARKDOWN)
        ---
        name: Bug
        about: Report a bug with the classic template.
        title:
          - "[Bug]"
        labels:
          invalid: mapping
        type: 7
        assignees: false
        unexpected: value
        ---

        Describe the bug.
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Classic issue template .github/ISSUE_TEMPLATE/classic.md has unpermitted key unexpected"
      assert_includes stderr, "Classic issue template .github/ISSUE_TEMPLATE/classic.md name must contain more than 3 characters"
      %w[title labels type assignees].each do |field|
        assert_includes stderr,
          "Classic issue template .github/ISSUE_TEMPLATE/classic.md #{field} must be a string"
      end
    end
  end

  def test_rejects_insecure_external_markdown_links
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write("[Insecure support](http://example.com/support)\n")

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "External link must use HTTPS in README.md: http://example.com/support"
    end
  end

  def test_ignores_markdown_link_syntax_in_non_rendered_code
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      write_readme_fixture(root, <<~MARKDOWN)
        Inline example: `[Support](http://inline-code.example/support)`
        Inline HTML example: `<a href="http://inline-html.example/support">Support</a>`

        ```markdown
        [Support](http://fenced-code.example/support)
        <http://fenced-autolink.example/support>
        <a href="http://fenced-html.example/support">Support</a>
        [guide]: http://fenced-reference.example/support
        ```

            [Support](http://indented-code.example/support)

        <!--
        [Support](http://comment.example/support)
        <a href="http://comment-html.example/support">Support</a>
        -->

        <div>
        [Support](http://raw-html.example/support)
        </div>
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_ignores_html_anchor_examples_inside_attributes
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      write_readme_fixture(root, <<~MARKDOWN)
        <div title='<a href="http://attribute.example/support">'>
        Safe text
        </div>
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_rejects_insecure_markdown_autolinks
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write(<<~MARKDOWN)
        Support: <http://example.com/support>
        Email: <mailto:>
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "External link must use HTTPS in README.md: http://example.com/support"
      assert_includes stderr, "Mail link needs a recipient in README.md: mailto:"
    end
  end

  def test_rejects_insecure_bare_urls_and_ignores_non_rendered_examples
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      readme = root.join("README.md")
      ignored_examples = <<~MARKDOWN
        Inline code: `http://inline.example/support`
        Escaped text: http\\://escaped.example/support
        <!-- http://comment.example/support -->

        `Multiline code starts
        http://multiline-code.example/support
        and ends here`

        ```text
        http://fenced.example/support
        ```

        > ```text
        > http://quoted-fence.example/support
        > ```

        >     http://quoted-indented.example/support

        - ```text
          http://listed-fence.example/support
          ```

        <div>
        http://raw-html-block.example/support
        </div>

        ~~~text
        ~~~~not-a-closing-fence
        http://continued-fence.example/support
        ~~~
      MARKDOWN
      readme.write("Insecure prose: http://example.com/support\n#{ignored_examples}")

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?, "validator accepted a rendered bare HTTP URL"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://example.com/support"
      refute_includes stderr, "http://inline.example/support"
      refute_includes stderr, "http://escaped.example/support"
      refute_includes stderr, "http://comment.example/support"
      refute_includes stderr, "http://fenced.example/support"
      refute_includes stderr, "http://multiline-code.example/support"
      refute_includes stderr, "http://quoted-fence.example/support"
      refute_includes stderr, "http://quoted-indented.example/support"
      refute_includes stderr, "http://listed-fence.example/support"
      refute_includes stderr, "http://raw-html-block.example/support"
      refute_includes stderr, "http://continued-fence.example/support"

      write_readme_fixture(root, ignored_examples)
      ignored_stdout, ignored_stderr, ignored_status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert ignored_status.success?, ignored_stderr
      ignored_count = ignored_stdout.match(/and (\d+) Markdown links\./)[1].to_i

      write_readme_fixture(root, <<~MARKDOWN)
        Secure prose: https://example.com/support
        Uppercase secure prose: HTTPS://secure.example/support
        #{ignored_examples}
      MARKDOWN
      secure_stdout, secure_stderr, secure_status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert secure_status.success?, secure_stderr
      secure_count = secure_stdout.match(/and (\d+) Markdown links\./)[1].to_i
      assert_equal ignored_count + 2, secure_count
    end
  end

  def test_rejects_bare_http_url_after_a_list_fence
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write(<<~MARKDOWN)
        - ```text
          https://inside-list-code.example/support
          ```

        Active prose: http://after-list-fence.example/support
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?, "validator hid prose after a list fence"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://after-list-fence.example/support"
      refute_includes stderr, "https://inside-list-code.example/support"
    end
  end

  def test_rejects_bare_http_url_after_a_code_span_paragraph
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write(<<~MARKDOWN)
        `code starts

        Active prose: http://after-code-paragraph.example/support
        code ends`
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?, "validator masked a URL across a paragraph boundary"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://after-code-paragraph.example/support"
    end
  end

  def test_rejects_bare_http_urls_across_nonblank_block_boundaries
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write(<<~MARKDOWN)
        `heading span starts
        # Heading http://span-heading.example/support
        heading span ends`

        `list span starts
        - http://span-list.example/support
        list span ends`
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?, "validator masked URLs across Markdown block boundaries"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://span-heading.example/support"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://span-list.example/support"
    end
  end

  def test_ignores_code_span_in_a_lazy_blockquote_continuation
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      write_readme_fixture(root, <<~MARKDOWN)
        > `code starts
        http://lazy-quote-code.example/support
        code ends`
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_rejects_bare_http_url_in_a_separate_table_cell
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write(<<~MARKDOWN)
        | A |
        | --- |
        | `start |
        | http://table-cell-active.example/support ` |
        | `http://table-cell-code.example/support` | http://table-row-active.example/support |
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?, "validator paired code delimiters across table cells"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://table-cell-active.example/support"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://table-row-active.example/support"
      refute_includes stderr, "http://table-cell-code.example/support"
    end
  end

  def test_ignores_indented_code_after_a_table
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      write_readme_fixture(root, <<~MARKDOWN)
        | A |
        | --- |
        | value |
            http://after-table.example/support
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_rejects_bare_http_url_between_escaped_backticks
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write(
        "\\`literal http://escaped-backtick.example/support \\`\n"
      )

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?, "validator treated escaped backticks as code delimiters"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://escaped-backtick.example/support"
    end
  end

  def test_rejects_bare_http_url_after_a_backslash_inside_code
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write(
        "`code \\` Active http://after-code.example/support `\n"
      )

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?, "validator extended a code span past its real closer"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://after-code.example/support"
    end
  end

  def test_rejects_bare_http_url_in_an_indented_paragraph_continuation
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write(<<~MARKDOWN)
        Paragraph continuation
            http://indented-continuation.example/support
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?, "validator treated paragraph prose as an indented code block"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://indented-continuation.example/support"
    end
  end

  def test_ignores_plain_url_text_in_raw_html_blocks
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      write_readme_fixture(root, <<~MARKDOWN)
        <div>
        http://raw-html-block.example/support
        </div>
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_ignores_indented_code_after_an_atx_heading
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      write_readme_fixture(root, <<~MARKDOWN)
        # Finished heading
            http://after-heading.example/support
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_ignores_indented_code_after_list_markers
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      write_readme_fixture(root, <<~MARKDOWN)
        -     http://list-indented.example/support
        1.     http://ordered-indented.example/support
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_keeps_noninterrupting_ordered_marker_inside_a_code_span
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      write_readme_fixture(root, <<~MARKDOWN)
        `code starts
        2. http://ordered-noninterrupt.example/support
        code ends`
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_ignores_gfm_raw_html_block_variants
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      write_readme_fixture(root, <<~MARKDOWN)
        <script
        http://script-block.example/support
        </script>

        <x-widget>
        http://custom-block.example/support
        </x-widget>

        - <div>
          http://listed-html-block.example/support
          </div>

        <div
        http://unterminated-div-block.example/support
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_rejects_bare_http_urls_after_markup_inside_fences
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write(<<~MARKDOWN)
        ```html
        <!--
        ```
        Active prose: http://after-comment-fence.example/support

        ```html
        <div>
        ```
        Active prose: http://after-html-fence.example/support
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?, "validator let fenced markup mask following prose"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://after-comment-fence.example/support"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://after-html-fence.example/support"
    end
  end

  def test_rejects_bare_http_urls_after_rendered_boundaries
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write(<<~MARKDOWN)
        Backslash boundary: \\http://backslash.example/support
        Underscore boundary: _http://underscore.example/support
        Unicode boundary: éhttp://unicode-boundary.example/support
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?, "validator accepted rendered bare HTTP URLs"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://backslash.example/support"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://underscore.example/support"
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://unicode-boundary.example/support"
    end
  end

  def test_reports_malformed_bare_external_urls_without_a_stack_trace
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      malformed_url = "https://example.com/%ZZ"
      root.join("README.md").write("Malformed prose: #{malformed_url}\n")

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?, "validator accepted a malformed bare URL"
      assert_includes stderr,
        "Invalid link in README.md: #{malformed_url}"
      refute_includes stderr, "URI::InvalidURIError"
      refute_includes stderr, "validate-community-files.rb:"
    end
  end

  def test_rejects_unsafe_html_anchor_targets
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      readme = root.join("README.md")
      readme.write(<<~MARKDOWN)
        <a href="http://example.com/support">Insecure support</a>
        <A HREF='javascript:alert(1)'>Unsafe action</A>
        <a href=mailto:>Missing recipient</a>
        <a href="">Missing target</a>
        <a href="https://user@example.com/private">Misleading host</a>
        <a href="../outside.md">Outside repository</a>
        <a href="missing.md">Missing file</a>
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://example.com/support"
      assert_includes stderr,
        "Unsupported link scheme in README.md: javascript:alert(1)"
      assert_includes stderr, "Mail link needs a recipient in README.md: mailto:"
      assert_includes stderr, "Empty Markdown link target in README.md"
      assert_includes stderr,
        "External link includes user information in README.md: https://user@example.com/private"
      assert_includes stderr,
        "Relative link escapes repository in README.md: ../outside.md"
      assert_includes stderr, "Broken relative link in README.md: missing.md"

      write_readme_fixture(root, <<~MARKDOWN)
        <a data-href="http://ignored.example" href="https://example.com/support">Secure support</a>
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_rejects_unsafe_html_anchor_after_less_than_prose
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write(<<~MARKDOWN)
        Keep usage < user's daily limit.
        <a href="http://example.com/support">Insecure support</a>
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr,
        "External link must use HTTPS in README.md: http://example.com/support"
    end
  end

  def test_does_not_double_count_angle_wrapped_inline_destinations
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      write_readme_fixture(root, "[Support](https://example.com/support)\n")

      plain_stdout, plain_stderr, plain_status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert plain_status.success?, plain_stderr

      write_readme_fixture(root, "[Support](<https://example.com/support>)\n")
      angle_stdout, angle_stderr, angle_status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert angle_status.success?, angle_stderr
      assert_equal plain_stdout, angle_stdout
    end
  end

  def test_accepts_gfm_inline_link_title_delimiters
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      write_readme_fixture(root, <<~MARKDOWN)
        [Double quoted](SUPPORT.md "Support")
        [Single quoted](SUPPORT.md 'Support')
        [Parenthesized](SUPPORT.md (Support))
        [Angle destination](<SUPPORT.md> 'Support')
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_validates_markdown_links_in_hidden_github_directories
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join(".github/pull_request_template.md").write(
        "[Insecure checklist](http://example.com/checklist)\n"
      )

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr,
        "External link must use HTTPS in .github/pull_request_template.md: http://example.com/checklist"
    end
  end

  def test_validates_reference_style_markdown_link_targets
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write(<<~MARKDOWN)
        Read the [missing guide][guide].
        Read the [undefined guide][undefined].

        [guide]: missing-guide.md
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Broken relative link in README.md: missing-guide.md"
      assert_includes stderr, "Undefined Markdown link reference in README.md: undefined"
    end
  end

  def test_matches_reference_labels_with_unicode_case_folding
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      readme_path = root.join("README.md")
      readme_path.write(<<~MARKDOWN)
        #{readme_path.read}

        Read the [security policy][STRASSE].

        [Straße]: SECURITY.md
      MARKDOWN

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr
    end
  end

  def test_rejects_empty_inline_markdown_link_targets
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write("[Missing destination]()\n")

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Empty Markdown link target in README.md"
    end
  end

  def test_rejects_mailto_links_without_recipients
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      root.join("README.md").write("[Missing email recipient](mailto:)\n")

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Mail link needs a recipient in README.md: mailto:"
    end
  end

  def test_treats_mailto_schemes_case_insensitively
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      readme_path = root.join("README.md")
      readme_path.write(
        "#{readme_path.read}\n[Security contact](MAILTO:security@example.com)\n"
      )

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      assert status.success?, stderr

      readme_path.write(readme_path.read.sub(
        "MAILTO:security@example.com",
        "MAILTO:"
      ))

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr, "Mail link needs a recipient in README.md: MAILTO:"
      refute_includes stderr, "Unsupported link scheme"
    end
  end

  def test_rejects_issue_templates_in_nested_directories
    Dir.mktmpdir("community-files") do |directory|
      root = Pathname(directory)
      copy_profile_files(root)
      nested_directory = root.join(".github/ISSUE_TEMPLATE/nested")
      nested_directory.mkpath
      nested_directory.join("hidden.yml").write(<<~YAML)
        name: Hidden form
        description: GitHub does not discover nested issue forms.
        body:
          - type: input
            attributes:
              label: Response
      YAML

      _stdout, stderr, status = Open3.capture3(
        { "COMMUNITY_FILES_ROOT" => root.to_s },
        "ruby",
        VALIDATOR.to_s
      )

      refute status.success?
      assert_includes stderr,
        "Issue template must be stored directly in .github/ISSUE_TEMPLATE: .github/ISSUE_TEMPLATE/nested/hidden.yml"
    end
  end

  private

  def write_readme_fixture(root, contents)
    source = REPOSITORY_ROOT.join("README.md").read
    identifiers = source[/## Current Proof Layer Identifiers\n\n.*?(?=\n## )/m]
    raise "Public identifier fixture section is missing" unless identifiers

    root.join("README.md").write("#{contents.rstrip}\n\n#{identifiers}\n")
  end

  def copy_profile_files(destination)
    %w[
      CODE_OF_CONDUCT.md
      CONTRIBUTING.md
      README.md
      SECURITY.md
      SUPPORT.md
    ].each do |filename|
      FileUtils.cp(REPOSITORY_ROOT.join(filename), destination.join(filename))
    end

    FileUtils.cp_r(REPOSITORY_ROOT.join(".github"), destination)
    FileUtils.cp_r(REPOSITORY_ROOT.join("profile"), destination)
  end
end
