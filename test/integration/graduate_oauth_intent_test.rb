# frozen_string_literal: true

# Failure cases written before middleware session-validation correction:
# expired graduate metadata must be cleared before a fresh login intent;
# inconsistent graduate metadata must never supply Passport York linking proof.
require 'test_helper'
require_relative '../support/graduate_oauth_flow'

class GraduateOAuthIntentTest < ActionDispatch::IntegrationTest
  include GraduateOAuthFlow

  setup do
    host! '127.0.0.1:3210'
    @student = create(:student)
    @forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    OmniAuth.config.test_mode = true
    mock_provider
    ppy_login(@student)
    complete_oauth
    fresh_browser
    complete_oauth
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
    Warden.test_reset!
  end

  test 'expired graduate metadata is removed before a fresh provider login intent' do
    token = session[:graduate_session_token]
    # Exact expiry is covered by GraduateSessionSecurityTest. Move past it here
    # so wall-clock microseconds cannot leave this middleware probe just early.
    travel 13.hours do
      start_oauth
      assert_equal 'login', session[:graduate_oauth_intent]['mode']
      assert_nil session[:user_id]
      assert_nil session[:graduate_session_token]
      assert GraduateSession.find_by!(token_digest: Digest::SHA256.hexdigest(token)).revoked_at
      follow_redirect!
      assert_equal @student.id, session[:user_id]
      assert_equal 'graduate_oauth', session[:auth_source]
      assert_not_equal token, session[:graduate_session_token]
    end
  end

  test 'inconsistent graduate metadata cannot be used as PPY linking proof' do
    attributes = session.to_hash.merge('auth_source' => 'ppy')
    key = Rails.application.config.session_options[:key]
    jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
    jar.signed_or_encrypted[key] = { value: attributes }
    headers = {}
    jar.write(headers)
    cookies.merge(headers['Set-Cookie'], URI.parse('http://127.0.0.1:3210/'))
    mock_provider(uid: 'unlinked-intent-subject')
    start_oauth
    assert_equal 'login', session[:graduate_oauth_intent]['mode']
    assert_nil session[:user_id]
    assert_no_difference('GraduateIdentity.count') { follow_redirect! }
    assert_nil @student.graduate_identities.find_by(uid: 'unlinked-intent-subject')
  end
end
