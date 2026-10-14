# frozen_string_literal: true

# These removal regressions and the failure scenarios precede application edits.
require 'test_helper'
require_relative '../support/graduate_oauth_flow'

class GoogleOnlyAuthenticationTest < ActionDispatch::IntegrationTest
  include GraduateOAuthFlow

  setup do
    host! '127.0.0.1:3210'
    @student = create(:student, name: 'Google Only Graduate')
    @forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    OmniAuth.config.test_mode = true
    mock_provider
    mock_provider('facebook', uid: 'removed-facebook-subject')
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
    Warden.test_reset!
  end

  test 'only Google appears in public login and configured providers' do
    assert_equal ['google_oauth2'], GraduateAuthentication.enabled_providers
    assert_equal ['google_oauth2'], GraduateAuthentication::PROVIDERS
    get graduate_login_path
    assert_response :success
    assert_select 'form[action=?]', graduate_auth_path('google_oauth2'), count: 1
    assert_select 'form[action=?]', graduate_auth_path('facebook'), count: 0
    assert_not_includes response.body, 'Facebook'
  end

  test 'Facebook initiation and callback are unavailable without authentication' do
    get graduate_login_path
    assert_no_difference(['GraduateIdentity.count', 'GraduateSession.count']) do
      post graduate_auth_path('facebook'), params: { authenticity_token: csrf_token }
      assert_response :not_found
      get graduate_auth_callback_path('facebook'), params: { code: 'obsolete-code', state: 'obsolete-state' }
      assert_response :not_found
    end
    assert_nil session[:user_id]
    assert_nil session[:graduate_oauth_intent]
    assert_not_includes response.body, 'Facebook'
  end

  test 'staff cannot issue a new Facebook invitation' do
    ppy_login(create(:user, role: User::MANAGER))
    get staff_student_graduate_connections_path(@student)
    assert_select 'select[name=provider] option[value=facebook]', count: 0
    assert_no_difference('GraduateAuthenticationInvitation.count') do
      post student_graduate_invitations_path(@student), params: {
        provider: 'facebook', identity_verified: '1', authenticity_token: csrf_token
      }
    end
    assert_redirected_to staff_student_graduate_connections_path(@student)
  end

  test 'legacy Facebook rows stay hidden and cannot enroll or block Google invitations' do
    manager = create(:user, role: User::MANAGER)
    legacy_identity = insert_legacy_identity
    raw_token = SecureRandom.urlsafe_base64(32)
    GraduateAuthenticationInvitation.insert_all!([{
      student_id: @student.id, approved_by_id: manager.id, provider: 'facebook',
      token_digest: Digest::SHA256.hexdigest(raw_token), expires_at: 48.hours.from_now,
      created_at: Time.current, updated_at: Time.current
    }])
    legacy_invitation = GraduateAuthenticationInvitation.find_by!(token_digest: Digest::SHA256.hexdigest(raw_token))
    ppy_login(@student)
    get graduate_connections_path
    assert_response :success
    assert_not_includes response.body, 'Facebook'
    assert_select 'form[action=?]', graduate_connection_path(legacy_identity), count: 0
    ppy_login(manager)
    get staff_student_graduate_connections_path(@student)
    assert_response :success
    assert_not_includes response.body, 'Facebook'
    assert_select 'select[name=provider] option[value=google_oauth2]', count: 1
    assert_select 'select[name=provider] option[value=facebook]', count: 0
    fresh_browser
    get graduate_enroll_path, params: { token: raw_token }
    assert_response :unprocessable_entity
    assert_nil session[:graduate_enrollment]
    assert_nil session[:user_id]
    assert_nil legacy_invitation.reload.consumed_at
    assert_not legacy_invitation.usable?
    invitation, url = invite(@student, approver: manager, provider: 'google_oauth2')
    assert invitation.usable?
    fresh_browser
    enter_invitation(url)
    assert_difference('GraduateIdentity.count', 1) { complete_oauth }
    assert_equal @student.id, session[:user_id]
    assert legacy_identity.reload
    assert_nil legacy_invitation.reload.consumed_at
  end

  test 'existing Facebook graduate cookie is rejected and its server session revoked' do
    ppy_login(@student)
    complete_oauth
    fresh_browser
    complete_oauth
    identity = @student.graduate_identities.find_by!(provider: 'google_oauth2')
    record = GraduateSession.find_by!(token_digest: Digest::SHA256.hexdigest(session[:graduate_session_token]))
    saved_cookie = cookies[Rails.application.config.session_options[:key]].dup
    # An already-persisted provider value models the legacy identity and cookie.
    identity.update_columns(provider: 'facebook')
    cookies[Rails.application.config.session_options[:key]] = saved_cookie
    get student_view_details_path
    assert_redirected_to login_path
    %i[user_id auth_source graduate_identity_id graduate_session_token].each { |key| assert_nil session[key] }
    assert record.reload.revoked_at
    assert_not_includes response.body, @student.name
    assert GraduateIdentity.exists?(identity.id)
  end

  test 'removed Facebook identity cannot receive a new graduate session' do
    identity = insert_legacy_identity
    assert_no_difference('GraduateSession.count') do
      assert_raises(GraduateAuthentication::Rejected) { GraduateSession.issue!(identity) }
    end
  end

  test 'Google UID linking and return sign in keep the existing contact email' do
    @student.update!(email_external: 'registered-external@example.invalid')
    original_email = @student.email
    original_external_email = @student.email_external
    mock_provider(email: 'different-personal@gmail.com')
    ppy_login(@student)
    complete_oauth
    assert_equal original_email, @student.reload.email
    assert_equal original_external_email, @student.email_external
    fresh_browser
    complete_oauth
    assert_equal @student.id, session[:user_id]
    assert_equal original_email, @student.reload.email
    assert_equal original_external_email, @student.email_external
    assert_not_includes GraduateIdentity.column_names, 'email'
    assert_not_includes @student.graduate_identities.first.attributes.to_json, 'different-personal@gmail.com'
  end

  private

  def insert_legacy_identity
    GraduateIdentity.insert_all!([{
      student_id: @student.id, provider: 'facebook', uid: 'legacy-facebook-subject',
      link_method: 'ppy', created_at: Time.current, updated_at: Time.current
    }])
    @student.graduate_identities.find_by!(provider: 'facebook')
  end
end
