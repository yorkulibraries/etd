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
end
