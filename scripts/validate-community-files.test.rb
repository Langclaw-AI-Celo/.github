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
