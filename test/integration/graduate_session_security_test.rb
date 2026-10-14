# frozen_string_literal: true

# Failure cases and these HTTP regressions precede the application correction.
# Provider success is mocked at the existing boundary; PPY headers, CSRF forms,
# encrypted cookies and private details requests use the ordinary Rails stack.
require 'test_helper'
require 'digest'
require_relative '../support/graduate_oauth_flow'

class GraduateSessionSecurityTest < ActionDispatch::IntegrationTest
  include GraduateOAuthFlow

  setup do
    host! '127.0.0.1:3210'
    @student = create(:student, name: 'Graduate Session Private Student')
    @forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    OmniAuth.config.test_mode = true
    mock_provider
    ppy_login(@student)
    complete_oauth
    @identity = @student.graduate_identities.find_by!(provider: 'google_oauth2')
    fresh_browser
  end

  teardown do
    travel_back
    ActionController::Base.allow_forgery_protection = @forgery
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
    Warden.test_reset!
  end

  test 'actual encrypted graduate cookie is rejected after logout' do
    external_login
    assert_private_details
    saved_cookie = encrypted_cookie
    get logout_path
    assert_redirected_to graduate_login_path
    assert_nil session[:user_id]
    assert_nil session[:graduate_session_token]

    replay_cookie(saved_cookie)
    assert_private_details_denied
    assert GraduateSession.find_by!(graduate_identity: @identity).revoked_at
  end

  test 'graduate session has an absolute twelve hour expiry despite activity' do
    travel_to Time.current.change(usec: 0)
    issued_at = Time.current
    external_login
    assert_private_details
    record = current_graduate_session
    assert_equal issued_at + 12.hours, record.expires_at

    travel_to issued_at + 11.hours
    assert_private_details
    travel_to issued_at + 12.hours - 1.second
    assert_private_details
    assert_equal issued_at + 12.hours, record.reload.expires_at
    saved_cookie = encrypted_cookie

    travel_to issued_at + 12.hours
    replay_cookie(saved_cookie)
    assert_private_details_denied
    assert record.reload.revoked_at
  end

  test 'legacy graduate cookie without a session token fails closed' do
    external_login
    assert_private_details
    replace_legacy_cookie(session.to_hash.except('graduate_session_token'))
    assert_private_details_denied
  end

  test 'legacy graduate markers cannot pass with a non graduate authentication source' do
    [nil, 'ppy', 'unknown'].each do |source|
      fresh_browser
      external_login
      assert_private_details
      attributes = session.to_hash.except('auth_source')
      attributes['auth_source'] = source unless source.nil?
      replace_legacy_cookie(attributes)
      assert_private_details_denied
    end
  end

  test 'legacy graduate markers without a user are cleared and revoked' do
    external_login
    record = current_graduate_session
    replace_legacy_cookie(session.to_hash.except('user_id'))
    assert_private_details_denied
    assert record.reload.revoked_at
  end

  test 'actual graduate cookie without its server session record fails closed' do
    external_login
    saved_cookie = encrypted_cookie
    current_graduate_session.delete
    replay_cookie(saved_cookie)
    assert_private_details_denied
  end

  test 'actual graduate cookie with a nonmatching token digest fails closed' do
    external_login
    saved_cookie = encrypted_cookie
    current_graduate_session.update_columns(token_digest: '0' * 64)
    replay_cookie(saved_cookie)
    assert_private_details_denied
  end

  test 'session record must match the cookie identity even for the same Student' do
    GraduateIdentity.insert_all!([{ student_id: @student.id, provider: 'facebook', uid: 'legacy-session-subject',
                                   link_method: 'ppy', created_at: Time.current, updated_at: Time.current }])
    other_identity = @student.graduate_identities.find_by!(provider: 'facebook')
    fresh_browser
    external_login
    record = current_graduate_session
    record.update_columns(graduate_identity_id: other_identity.id)
    assert_private_details_denied
    assert record.reload.revoked_at
  end

  test 'session identity must still belong to the cookie Student' do
    external_login
    other_student = create(:student)
    @identity.update_columns(student_id: other_student.id)
    assert_private_details_denied
  end

  test 'blocking revokes the actual graduate cookie even after unblocking' do
    external_login
    assert_private_details
    saved_cookie = encrypted_cookie
    record = current_graduate_session
    @student.update!(blocked: true)
    assert_private_details_denied
    assert record.reload.revoked_at

    @student.update!(blocked: false)
    replay_cookie(saved_cookie)
    assert_private_details_denied
  end

  test 'PPY unlink still succeeds and rejects the saved graduate cookie' do
    external_login
    assert_private_details
    saved_cookie = encrypted_cookie
    fresh_browser
    ppy_login(@student)
    get graduate_connections_path
    delete graduate_connection_path(@identity), params: {
      confirmation: '1', authenticity_token: csrf_token
    }
    assert_redirected_to graduate_connections_path
    assert_not GraduateIdentity.exists?(@identity.id)
    assert_private_details

    replay_cookie(saved_cookie)
    assert_private_details_denied
  end

  test 'same browser sign in rotates and revokes its previous graduate session' do
    external_login
    assert_private_details
    previous_cookie = encrypted_cookie
    previous_record = current_graduate_session
    previous_token = session[:graduate_session_token]

    external_login
    assert_private_details
    assert_not_equal previous_token, session[:graduate_session_token]
    assert previous_record.reload.revoked_at
    assert_nil current_graduate_session.revoked_at
    current_cookie = encrypted_cookie

    replay_cookie(previous_cookie)
    assert_private_details_denied
    replay_cookie(current_cookie)
    assert_private_details
  end

  test 'rotation and logout preserve the other browser graduate session' do
    external_login
    assert_private_details
    other_browser_cookie = encrypted_cookie
    other_browser_record = current_graduate_session
    fresh_browser
    external_login
    first_token = session[:graduate_session_token]
    external_login
    assert_not_equal first_token, session[:graduate_session_token]
    get logout_path
    assert_redirected_to graduate_login_path

    replay_cookie(other_browser_cookie)
    assert_private_details
    assert_nil other_browser_record.reload.revoked_at
  end

  test 'fresh PPY login revokes the previous graduate session and stays valid after twelve hours' do
    external_login
    saved_cookie = encrypted_cookie
    record = current_graduate_session
    ppy_login(@student)
    assert record.reload.revoked_at
    assert_nil session[:graduate_session_token]
    assert_nil session[:graduate_identity_id]

    travel 13.hours do
      assert_private_details
      assert_equal 'ppy', session[:auth_source]
    end
    ppy_cookie = encrypted_cookie
    replay_cookie(saved_cookie)
    assert_private_details_denied
    replay_cookie(ppy_cookie)
    assert_private_details
    get logout_path
    assert_redirected_to 'https://passportyork.yorku.ca/ppylogin/ppylogout'
  end

  test 'PPY login and connection create no graduate sessions and legacy PPY remains valid' do
    assert_no_difference('GraduateSession.count') do
      @identity.destroy!
      ppy_login(@student)
      complete_oauth
    end
    assert_equal 'ppy', session[:auth_source]
    assert_nil session[:graduate_session_token]
    assert_nil session[:graduate_identity_id]
    replace_legacy_cookie(session.to_hash.except('auth_source'))
    travel 13.hours do
      assert_private_details
      assert_nil session[:auth_source]
    end
  end

  test 'PPY and legacy support keep blocked Student access for active staff' do
    @student.update!(blocked: true)
    [User::ADMIN, User::MANAGER, User::STAFF].each do |role|
      [false, true].each do |legacy|
        fresh_browser
        actor = create(:user, role: role)
        assert_no_difference('GraduateSession.count') do
          ppy_login(actor)
          replace_legacy_cookie(session.to_hash.except('auth_source')) if legacy
          get login_as_student_path(@student)
          assert_redirected_to student_view_index_path
          assert_private_details
          assert_equal actor.id, session[:return_to_user_id]
          assert_nil session[:graduate_session_token]
          get logout_as_student_path
          assert_redirected_to student_path(@student)
          assert_equal actor.id, session[:user_id]
          assert_nil session[:return_to_user_id]
        end
      end
    end
  end

  test 'Google issues digest only sessions with filtered tokens and no secret audits' do
    fresh_browser
    external_login
    assert_private_details
    token = session[:graduate_session_token]
    assert_match(/\A[0-9a-f]{64}\z/, token)
    record = current_graduate_session
    assert_equal Digest::SHA256.hexdigest(token), record.token_digest
    assert_equal session[:graduate_identity_id], record.graduate_identity_id
    assert_not_includes GraduateSession.column_names, 'token'
    assert_not_includes GraduateSession.column_names, 'graduate_session_token'
    database_text = GraduateSession.all.map(&:attributes).to_json
    audit_text = Audited.audit_class.all.map(&:attributes).to_json
    [token, 'NEVER_STORE_ACCESS_TOKEN', 'NEVER_STORE_REFRESH_TOKEN'].each do |secret|
      assert_not_includes database_text, secret
      assert_not_includes audit_text, secret
    end
    assert_not Audited.audit_class.where(auditable_type: 'GraduateSession').exists?
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    assert_equal '[FILTERED]', filtered.filter(graduate_session_token: token)[:graduate_session_token]
  end

  private

  def external_login(provider = 'google_oauth2')
    complete_oauth(provider)
    assert_equal @student.id, session[:user_id]
    assert_equal 'graduate_oauth', session[:auth_source]
  end

  def assert_private_details
    get student_view_details_path
    assert_response :success
    assert_includes response.body, @student.name
  end

  def assert_private_details_denied
    get student_view_details_path
    assert_redirected_to login_path
    assert_nil session[:user_id]
    assert_nil session[:auth_source]
    assert_nil session[:graduate_identity_id]
    assert_nil session[:graduate_session_token]
    assert_not_includes response.body, @student.name
  end

  def current_graduate_session
    GraduateSession.find_by!(token_digest: Digest::SHA256.hexdigest(session[:graduate_session_token]))
  end

  def encrypted_cookie
    value = cookies[Rails.application.config.session_options[:key]]
    assert value.present?, 'Rails must issue an encrypted session cookie before replay'
    value.dup
  end

  def replay_cookie(value)
    cookies[Rails.application.config.session_options[:key]] = value
  end

  # Compatibility fixtures represent an already-issued, Rails-encrypted session
  # predating the new token or auth_source field. Replay tests never forge cookies.
  def replace_legacy_cookie(attributes)
    key = Rails.application.config.session_options[:key]
    jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
    jar.signed_or_encrypted[key] = { value: attributes }
    headers = {}
    jar.write(headers)
    cookies.merge(headers['Set-Cookie'], URI.parse('http://127.0.0.1:3210/'))
    value = jar.signed_or_encrypted[key]['user_id']
    attributes['user_id'].nil? ? assert_nil(value) : assert_equal(attributes['user_id'], value)
  end
end
