# frozen_string_literal: true
require 'test_helper'
require 'action_dispatch/system_test_case'
require_relative '../support/graduate_system_helpers'

# F02 F21: no browser is started; spies stand at the actual Rails capture boundary.
class GraduateEmailArtifactsTest < ActiveSupport::TestCase
  class TeardownBase
    def before_teardown; end
  end
  class Harness < TeardownBase
    include ActionDispatch::SystemTesting::TestHelpers::SetupAndTeardown
    include ActionDispatch::SystemTesting::TestHelpers::ScreenshotHelper
    include GraduateSystemHelpers
    attr_reader :calls
    def initialize
      @calls = []
      @secret_page = { url: 'http://example.invalid/?token=ARTIFACT_SENTINEL',
        form: 'ARTIFACT_SENTINEL', mail: 'ARTIFACT_SENTINEL' }
    end
    def current_window; @calls << :window; raise 'unsafe driver reached'; end
    def page; @calls << :page; raise 'unsafe driver reached'; end
    def passed?; false; end
    def skipped?; false; end
    def save_html; @calls << :html; end
    def save_image; @calls << :image; end
    def display_image; 'capture reached'; end
  end

  test 'failure_artifacts_never_save_secret_page' do
    ENV['RAILS_SYSTEM_TESTING_SCREENSHOT_HTML'] = '1'
    harness = Harness.new
    before = Dir.glob(Rails.root.join('tmp/**/*.{html,png}')).sort
    output, = capture_io { harness.take_screenshot }
    assert Dir.glob(Rails.root.join('tmp/**/*.{html,png}')).sort == before, 'capture must create no files'
    assert harness.calls.empty?, 'capture boundary must remain untouched'
    assert output.empty?, 'report must remain empty'
  ensure
    ENV.delete('RAILS_SYSTEM_TESTING_SCREENSHOT_HTML')
  end

  test 'legacy_google_generated_token_is_never_captured' do
    harness = Harness.new
    harness.browser_artifact('generated-url')
    harness.browser_artifact('generated-url-mobile', mobile: true)
    assert harness.calls.empty?, 'legacy token screen must never reach driver'
    source = Rails.root.join('test/system/graduate_authentication_test.rb').read
    refute source.include?("browser_artifact('generated-url"), 'legacy capture calls must be removed'
  end

  test 'unsafe_capture_fails_closed_before_driver_or_failure_hook' do
    [Minitest::Assertion.new('static assertion'), RuntimeError.new('static error')].each do |failure|
      harness = Harness.new
      harness.define_singleton_method(:failure) { failure }
      output, = capture_io do
        harness.before_teardown
        harness.take_failed_screenshot
        harness.send(:save_html)
        harness.send(:save_image)
        harness.browser_artifact('sentinel?token=DO_NOT_CAPTURE')
      end
      assert harness.calls.empty?, 'automatic and explicit hooks must fail closed'
      assert output.empty?, 'failure report must contain no page data'
    end
  end
  test 'report_manifest_contains_no_mail_or_token' do
    require 'tmpdir'
    Dir.mktmpdir do |dir|
      sentinel = 'TASK7_ARTIFACT_SENTINEL'
      output = "GraduateEmailArtifactsTest#test_report_manifest_contains_no_mail_or_token = 0.1 s = .\nRuntimeError: #{sentinel} recipient@example.org https://example.invalid/?token=secret\n1 runs, 2 assertions, 0 failures, 0 errors, 0 skips\n"
      report = GraduateEmailSafeArtifacts.sanitize_report(output)
      assert report.include?('1 runs, 2 assertions'), 'counts retained'
      refute report.include?(sentinel), 'sentinel excluded'
      refute report.include?('@'), 'recipient excluded'
      File.write(File.join(dir, 'integration.txt'), report)
      metadata = {adapter: 'sqlite', seed: 12345, head: 'a' * 40, source_sha256: 'b' * 64, diff_sha256: 'c' * 64, branch: 'graduate-email-otp'}
      GraduateEmailSafeArtifacts.write_manifest(dir, metadata: metadata)
      assert GraduateEmailSafeArtifacts.scan!(dir, sentinels: [sentinel]), 'clean scan'
      manifest = File.read(File.join(dir, 'manifest.json'))
      refute manifest.include?(sentinel), 'manifest excludes secret'
      File.write(File.join(dir, 'raw.log'), sentinel)
      assert_raises(GraduateEmailSafeArtifacts::UnsafeArtifact) { GraduateEmailSafeArtifacts.write_manifest(dir, metadata: metadata) }
      File.delete(File.join(dir, 'raw.log'))
      File.write(File.join(dir, 'integration.txt'), sentinel)
      assert_raises(GraduateEmailSafeArtifacts::UnsafeArtifact) { GraduateEmailSafeArtifacts.scan!(dir) }
      File.delete(File.join(dir, 'integration.txt'))
      File.symlink('/dev/null', File.join(dir, 'integration.txt'))
      assert_raises(GraduateEmailSafeArtifacts::UnsafeArtifact) { GraduateEmailSafeArtifacts.scan!(dir) }
    end
  end

  test 'only_allowlisted_clean_states_can_capture' do
    clean = {path: '/graduate/email/verify', query: false, secret: false, entered: false,
      heading: 'Enter your sign-in code', width: 390, height: 844}
    assert GraduateEmailSafeArtifacts.clean_state?('code-error', clean), 'documented clean state'
    [{query: true}, {secret: true}, {entered: true}, {path: '/other'}, {heading: 'Share this invitation once'}].each do |bad|
      refute GraduateEmailSafeArtifacts.clean_state?('code-error', clean.merge(bad)), 'unsafe state rejected'
    end
    refute GraduateEmailSafeArtifacts.clean_state?('../code-error', clean), 'unknown name rejected'
    refute GraduateEmailSafeArtifacts.clean_state?('generated-url', clean), 'Google token state rejected'
  end

end
