# frozen_string_literal: true

require_relative '../support/graduate_oauth_environment'
require 'test_helper'
require_relative '../support/graduate_system_helpers'

# Deliberately independent of ApplicationSystemTestCase's automatic staff login.
class GraduateAuthenticationSystemTest < ActionDispatch::SystemTestCase
  include GraduateSystemHelpers

  driven_by :selenium, using: :headless_chrome, screen_size: [1440, 1000] do |options|
    chrome_binary = ENV['CHROME_BIN'].presence || ('/usr/bin/chromium' if File.executable?('/usr/bin/chromium'))
    options.binary = chrome_binary if chrome_binary
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--disable-gpu')
  end

  class_attribute :ppy_boundary

  def self.start_application
    self.ppy_boundary ||= GraduateSystemPpyBoundary.shared
    Capybara.app = ppy_boundary
    Capybara.server_host = '127.0.0.1'
    Capybara.server_port = ENV.fetch("ETD_SYSTEM_TEST_PORT", "3210").to_i
    Capybara.app_host = "http://127.0.0.1:#{Capybara.server_port}"
    ActionDispatch::SystemTesting::Server.new.run
  end

  setup do
    @previous_capybara_settings = {
      app: Capybara.app, server_host: Capybara.server_host,
      server_port: Capybara.server_port, app_host: Capybara.app_host,
      default_max_wait_time: Capybara.default_max_wait_time, save_path: Capybara.save_path
    }
    self.class.start_application
    @previous_test_mode = OmniAuth.config.test_mode
    @previous_mock_auth = OmniAuth.config.mock_auth.dup
    @previous_forgery_protection = ActionController::Base.allow_forgery_protection
    @previous_application_forgery_protection = ApplicationController.allow_forgery_protection
    OmniAuth.config.test_mode = true
    ActionController::Base.allow_forgery_protection = true
    ApplicationController.allow_forgery_protection = true
    Capybara.default_max_wait_time = 5
    Capybara.save_path = Rails.root.join('tmp/graduate-authentication/screenshots').to_s
    Warden.test_reset!
    self.class.ppy_boundary.login_headers = nil
    ActionMailer::Base.deliveries.clear
    browser_mock_provider
    current_window.resize_to(1440, 1000)
  end

  teardown do
    self.class.ppy_boundary.login_headers = nil
    OmniAuth.config.test_mode = @previous_test_mode
    OmniAuth.config.mock_auth = @previous_mock_auth
    ActionController::Base.allow_forgery_protection = @previous_forgery_protection
    ApplicationController.allow_forgery_protection = @previous_application_forgery_protection
    Warden.test_reset!
  end

  def after_teardown
    super
  ensure
    @previous_capybara_settings&.each { |setting, value| Capybara.public_send("#{setting}=", value) }
  end

  test 'anonymous login has configured POST buttons and fits desktop and mobile' do
    visit graduate_login_path
    assert_selector 'h1', text: 'Graduate sign in'
    assert_link 'Sign in with Passport York', href: login_path
    assert_no_selector 'input:not([type="hidden"]):not([type="submit"])'
    assert_selector 'meta[name="csrf-token"]', visible: :all
    assert_button 'Continue with Google'
    assert_no_link 'Email me a sign-in code'
    assert_no_button 'Continue with Facebook'
    GraduateAuthentication.enabled_providers.each do |provider|
      within "form[action='#{graduate_auth_path(provider)}'][method='post']" do
        assert_selector 'input[name="authenticity_token"]', visible: :all
        assert_button "Continue with #{GraduateAuthentication.label(provider)}"
      end
      assert_no_link href: graduate_auth_path(provider)
    end
    browser_artifact('login-desktop')
    browser_artifact('login-mobile', mobile: true)
  end

  test 'anonymous visitors reach the combined sign in from the home page' do
    browser_fresh_session
    visit root_path
    assert_current_path graduate_login_path
    assert_selector 'h1', text: 'Graduate sign in'
    assert_button 'Continue with Google'
    assert_link 'Sign in with Passport York', href: login_path
    browser_artifact('anonymous-home-sign-in')
  end

  test 'old Facebook records stay hidden in student settings and staff invitations' do
    student = create(:student, name: 'Synthetic Google Only Graduate')
    manager = create(:user, role: User::MANAGER)
    GraduateIdentity.insert_all!([{
      student_id: student.id, provider: 'facebook', uid: 'legacy-browser-facebook',
      link_method: 'ppy', created_at: Time.current, updated_at: Time.current
    }])
    GraduateAuthenticationInvitation.insert_all!([{
      student_id: student.id, approved_by_id: manager.id, provider: 'facebook',
      token_digest: Digest::SHA256.hexdigest(SecureRandom.urlsafe_base64(32)),
      expires_at: 48.hours.from_now, created_at: Time.current, updated_at: Time.current
    }])
    browser_ppy_login(student)
    visit graduate_connections_path
    assert_text 'No graduate accounts are connected yet.'
    assert_button 'Connect Google'
    assert_no_text 'Facebook'
    browser_artifact('google-only-legacy-settings')
    browser_artifact('google-only-legacy-settings-mobile', mobile: true)
    browser_fresh_session
    browser_ppy_login(manager)
    visit staff_student_graduate_connections_path(student)
    assert_selector 'select#provider option', text: 'Google', count: 1
    assert_no_selector 'select#provider option[value="facebook"]'
    assert_no_text 'Facebook'
    browser_artifact('google-only-legacy-staff')
    browser_artifact('google-only-legacy-staff-mobile', mobile: true)
    assert_equal 1, student.graduate_identities.count
    assert_equal 1, student.graduate_authentication_invitations.count
  end

  test 'login hides disabled providers and explains when none are available' do
    GraduateAuthentication.stubs(:enabled_providers).returns(['google_oauth2'])
    visit graduate_login_path
    assert_button 'Continue with Google'
    assert_no_button 'Continue with Facebook'
    GraduateAuthentication.stubs(:enabled_providers).returns([])
    visit graduate_login_path
    assert_text 'Graduate account sign in is currently unavailable.'
    assert_no_button 'Continue with Google'
    assert_no_button 'Continue with Facebook'
    assert_link 'Sign in with Passport York'
    GraduateAuthentication.unstub(:enabled_providers)
    visit graduate_auth_path('unavailable-provider')
    assert_text 'This sign-in option is unavailable.'
    assert_no_button 'Continue with Google'
    assert_no_button 'Continue with Facebook'
  end

  test 'actual PPY student connects returns socially and removes only with confirmation' do
    student = create(:student, name: 'Synthetic Graduate Student')
    browser_ppy_login(student)
    find('.navbar .dropdown-toggle').click
    click_link 'Account connections'
    assert_current_path graduate_connections_path
    assert_text 'No graduate accounts are connected yet.'
    click_button 'Connect Google'
    assert_text 'Linked on'
    assert_current_path graduate_connections_path
    identity = student.graduate_identities.find_by!(provider: 'google_oauth2')
    assert_no_text 'browser-google-subject'
    assert_required_checkbox "remove_identity_#{identity.id}"
    browser_artifact('settings-desktop')
    browser_artifact('settings-mobile', mobile: true)

    # Native browser validity stops an unchecked removal before it reaches Rails.
    click_button 'Remove Google connection'
    assert_equal 1, student.graduate_identities.count
    assert_selector "#remove_identity_#{identity.id}:invalid"

    browser_fresh_session
    visit graduate_login_path
    click_button 'Continue with Google'
    assert_current_path student_view_index_path
    visit student_view_details_path
    assert_text student.name
    find('.navbar .dropdown-toggle').click
    click_link 'Account connections'
    assert_text 'sign in with Passport York as yourself'
    assert_no_button 'Connect Facebook'
    assert_no_button 'Remove Google connection'

    browser_fresh_session
    browser_ppy_login(student)
    visit graduate_connections_path
    check "remove_identity_#{identity.id}"
    click_button 'Remove Google connection'
    assert_text 'No graduate accounts are connected yet.'
    assert_equal 0, student.graduate_identities.count
  end

  test 'verified staff invitation is copyable and enrolls once without email' do
    student = create(:student, name: 'Synthetic Invited Graduate')
    manager = create(:user, role: User::MANAGER, name: 'Synthetic FGS Manager')
    browser_ppy_login(manager)
    visit student_path(student)
    click_link 'Graduate account connections'
    assert_current_path staff_student_graduate_connections_path(student)
    assert_text 'outside this app'
    assert_required_checkbox 'identity_verified'
    select 'Google', from: 'Account provider'
    browser_artifact('staff-invitation')
    browser_artifact('staff-invitation-mobile', mobile: true)
    click_button 'Create invitation'
    assert_selector '#identity_verified:invalid'
    assert_equal 0, GraduateAuthenticationInvitation.count
    find('#identity_verified').send_keys(:escape, :space)
    assert find('#identity_verified').checked?
    click_button 'Create invitation'
    assert_selector 'h1', text: 'Graduate account invitation created'
    field = find_field('Invitation URL')
    assert_equal 'true', field[:readonly]
    invitation_url = field.value
    assert_match(%r{\A#{Regexp.escape(Capybara.app_host)}/}, invitation_url)
    assert_text '48 hours'
    assert_text 'No email has been sent'
    assert_empty ActionMailer::Base.deliveries
    invitation = GraduateAuthenticationInvitation.order(:id).last
    assert_in_delta 48.hours, invitation.expires_at - invitation.created_at, 5

    browser_fresh_session
    visit invitation_url
    assert_selector 'h1', text: 'Connect your graduate account'
    assert_current_path graduate_login_path
    assert_button 'Continue with Google'
    assert_no_button 'Continue with Facebook'
    assert_equal 0, student.graduate_identities.count
    browser_artifact('enrollment-desktop')
    browser_artifact('enrollment-mobile', mobile: true)
    click_button 'Continue with Google'
    assert_current_path student_view_index_path
    assert_equal 1, student.graduate_identities.where(provider: 'google_oauth2').count
    visit student_view_details_path
    assert_text student.name
    assert_empty ActionMailer::Base.deliveries

    browser_fresh_session
    visit invitation_url
    assert_selector '[role="alert"]'
    assert_no_selector 'h1', text: 'Connect your graduate account'
    assert_equal 1, student.graduate_identities.count

    browser_fresh_session
    browser_ppy_login(manager)
    visit staff_student_graduate_connections_path(student)
    identity = student.graduate_identities.find_by!(provider: 'google_oauth2')
    assert_required_checkbox "remove_identity_#{identity.id}"
    click_button 'Remove Google connection'
    assert_equal 1, student.graduate_identities.count
    find('body').send_keys(:escape)
    check "remove_identity_#{identity.id}"
    assert find("#remove_identity_#{identity.id}").checked?
    click_button 'Remove Google connection'
    assert_text 'No graduate accounts are connected yet.'
    assert_equal 0, student.graduate_identities.count
  end

  test 'cancelled and unlinked social accounts return actionable public failures' do
    OmniAuth.config.mock_auth[:google_oauth2] = :access_denied
    visit graduate_login_path
    click_button 'Continue with Google'
    assert_current_path graduate_login_path
    assert_selector '[role="alert"]'
    assert_link 'Sign in with Passport York'
    assert_no_text 'access_denied'

    browser_mock_provider(uid: 'unlinked-browser-subject')
    click_button 'Continue with Google'
    assert_current_path graduate_login_path
    assert_selector '[role="alert"]'
    assert_no_text 'unlinked-browser-subject'
    assert_text 'Faculty of Graduate Studies'
  end

  test 'ordinary staff sees no management link and blocked students cannot be invited' do
    student = create(:student, name: 'Synthetic Blocked Graduate', blocked: true)
    staff = create(:user, role: User::STAFF)
    browser_ppy_login(staff)
    visit student_path(student)
    assert_no_link 'Graduate account connections'

    browser_fresh_session
    manager = create(:user, role: User::MANAGER)
    browser_ppy_login(manager)
    visit staff_student_graduate_connections_path(student)
    assert_text 'Connections cannot be changed'
    assert_no_button 'Create invitation'
    assert_no_selector '#identity_verified'
  end
end
