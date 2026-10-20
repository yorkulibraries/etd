# frozen_string_literal: true
require_relative 'graduate_oauth_environment'
require 'test_helper'
require_relative 'graduate_system_helpers'
require_relative 'graduate_email_flow_helpers'

# Independent harness: never ApplicationSystemTestCase's implicit staff login.
class GraduateEmailBrowserCase < ActionDispatch::SystemTestCase
  include GraduateSystemHelpers
  include GraduateEmailFlowHelpers
  self.use_transactional_tests = false
  class_attribute :ppy_boundary
  driven_by :selenium, using: :headless_chrome, screen_size: [1440, 1000] do |options|
    options.binary = ENV['CHROME_BIN'].presence || '/usr/bin/chromium'
    %w[--no-sandbox --disable-dev-shm-usage --disable-gpu].each { |arg| options.add_argument(arg) }
  end

  def self.start_application
    self.ppy_boundary ||= GraduateSystemPpyBoundary.shared
    Capybara.app = ppy_boundary
    Capybara.server_host = '127.0.0.1'
    Capybara.server_port = ENV.fetch('ETD_SYSTEM_TEST_PORT', '3321').to_i
    Capybara.app_host = "http://127.0.0.1:#{Capybara.server_port}"
    ActionDispatch::SystemTesting::Server.new.run
  end

  setup do
    setup_flow
    @settings = {app: Capybara.app, server_host: Capybara.server_host, server_port: Capybara.server_port,
      app_host: Capybara.app_host, default_max_wait_time: Capybara.default_max_wait_time}
    self.class.start_application
    @app_forgery_inherited = !ApplicationController.config.key?(:allow_forgery_protection)
    @forgery = [ActionController::Base.allow_forgery_protection, ApplicationController.allow_forgery_protection]
    ActionController::Base.allow_forgery_protection = ApplicationController.allow_forgery_protection = true
    Capybara.default_max_wait_time = 5
    browser_fresh_session
  end
  teardown do
    browser_fresh_session
    ActionController::Base.allow_forgery_protection = @forgery.first
    if @app_forgery_inherited
      ApplicationController.config.delete(:allow_forgery_protection)
    else
      ApplicationController.allow_forgery_protection = @forgery.last
    end
    teardown_delivery
  end

  def after_teardown
    super
  ensure
    @settings&.each { |key, value| Capybara.public_send("#{key}=", value) }
  end

  def request_login(address = 'approved@example.com')
    visit '/graduate/email'
    fill_in 'Email address', with: address
    click_button 'Email me a sign-in code'
    assert_current_path '/graduate/email/challenges'
    assert_selector 'h1', text: 'Enter your sign-in code'
  end

  # Real persisted Delayed Job, synthetic RAM transport, real digest verification.
  def run_mail_worker
    row = GraduateEmailChallenge.where(state: 'queued').order(:id).last
    assert row, 'queued challenge exists'
    @capturing_id = row.public_id
    GraduateAuthenticationMailer.stub(:transport_class, @transport) do
      worker = Delayed::Worker.new(queues: [GraduateEmail::Limits::QUEUE], quiet: true)
      worker.run(Delayed::Job.where(queue: GraduateEmail::Limits::QUEUE).order(:id).last)
    end
    @capturing_id = nil
    [row, otp_code_for(public_id: row.public_id)]
  end

  def resend_code
    click_button 'Resend code'
    assert_current_path '/graduate/email/resend'
    assert_selector 'h1', text: 'Enter your sign-in code'
  end

  def enter_code(code)
    fill_in 'Sign-in code', with: code
    click_button 'Verify code'
  end

  def assert_generic_form
    assert_selector 'h1', text: 'Enter your sign-in code'
    assert_text 'If this address is enabled for graduate sign-in, we’ll send a code.'
    assert_selector 'input[type="text"][inputmode="numeric"][autocomplete="one-time-code"][maxlength="6"]'
    assert_button 'Resend code'
    assert_link 'Continue with Google'
    assert_link 'Sign in with Passport York'
  end
end
