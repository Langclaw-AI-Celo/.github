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
