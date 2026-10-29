# frozen_string_literal: true
require 'bundler/setup'
require 'logger'
require 'rails/test_unit/runner'

# One definition for the sealed OTP runner and the complementary CI suites.
# Ask the installed Rails runner for discovery, including its environment overrides.
module GraduateEmailTestSelection
  class InvalidSelection < StandardError; end
  EXISTING_INTEGRATION = %w[google_only_authentication graduate_authentication
    graduate_downloads graduate_staff_boundaries graduate_impersonation
    graduate_thesis_ownership graduate_session_security graduate_oauth_transaction
    graduate_oauth_intent graduate_oauth_lifecycle].freeze
  SYSTEM = %w[graduate_email_authentication graduate_email_management
    graduate_authentication graduate_downloads].freeze
  GROUPS = %w[focused_application focused_system application system].freeze

  def self.partitions
    discover = ->(args) { Rails::TestUnit::Runner.send(:list_tests, args).to_a.sort }
    application = discover.call([])
    system = discover.call(['test/system'])
    otp = Dir['test/integration/graduate_email_*_test.rb'].sort
    raise InvalidSelection if otp.empty?
    focused_application = otp + EXISTING_INTEGRATION.map { |name| "test/integration/#{name}_test.rb" }
    focused_system = SYSTEM.map { |name| "test/system/#{name}_test.rb" }
    groups = {'focused_application' => focused_application.sort, 'focused_system' => focused_system.sort,
      'application' => application - focused_application, 'system' => system - focused_system}
    expected = application + system
    assigned = groups.values.flatten
    # Explicit commands must load exactly the discovered files. Reject missing
    # expected files, overrides that drop focus, overlap and empty default fallback.
    valid = groups.values.all? do |files|
      !files.empty? && files.all? { |path| File.file?(path) } && discover.call(files) == files
    end
    raise InvalidSelection unless valid && expected.uniq.size == expected.size &&
      assigned.uniq.size == assigned.size && assigned.sort == expected.sort
    groups
  end

  def self.files(group)
    raise InvalidSelection unless GROUPS.include?(group)
    partitions.fetch(group)
  end

  def self.seed
    value = ENV.fetch('ETD_SYSTEM_TEST_SEED', '')
    value = '27183' if value.empty?
    raise InvalidSelection unless value.match?(/\A[0-9]+\z/)
    value
  end
end
