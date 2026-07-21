# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"

REPOSITORY_ROOT = Pathname(__dir__).join("..").expand_path
VALIDATOR = REPOSITORY_ROOT.join("scripts/validate-community-files.rb")

class CommunityFilesValidatorTest < Minitest::Test
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
