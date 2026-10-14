# frozen_string_literal: true

require_relative '../support/graduate_oauth_environment'
require 'test_helper'
require_relative '../support/graduate_oauth_flow'

class GraduateAuthenticationTest < ActionDispatch::IntegrationTest
  include GraduateOAuthFlow

  setup do
    host! '127.0.0.1:3210'
    @student = create(:student)
    @thesis = create(:thesis, student: @student)
    @forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    OmniAuth.config.test_mode = true
    mock_provider
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
    Warden.test_reset!
  end

  test 'fresh PPY headers preserve routing username update and true provenance' do
    @student.update!(username: @student.sisid)
    get login_path, headers: { 'HTTP_PYORK_CYIN' => @student.sisid, 'HTTP_PYORK_USER' => 'new_ppy_name' }
    assert_equal @student.id, session[:user_id]
    assert_equal 'ppy', session[:auth_source]
    assert_equal 'new_ppy_name', @student.reload.username
    assert_redirected_to student_view_index_path
    ppy_login(create(:user))
    assert_redirected_to root_path
  end

  test 'PPY connect then external return resolves the same student and thesis' do
    ppy_login(@student)
    assert_difference('GraduateIdentity.count', 1) { complete_oauth }
    identity = @student.graduate_identities.first
    assert_equal 'stable-google-subject', identity.uid
    assert_equal 'ppy', session[:auth_source]
    fresh_browser
    complete_oauth
    assert_equal @student.id, session[:user_id]
    assert_equal 'graduate_oauth', session[:auth_source]
    assert_equal identity.id, session[:graduate_identity_id]
    get student_view_thesis_process_path(@thesis, Thesis::PROCESS_BEGIN)
    assert_response :success
    assert_includes response.body, @thesis.title
    assert_equal User::STUDENT, @student.reload.role
  end

  test 'staff PPY with CYIN uses trusted username and inconsistent known identities are rejected' do
    staff = create(:user)
    get login_path, headers: { 'HTTP_PYORK_CYIN' => '987654321', 'HTTP_PYORK_USER' => staff.username }
    assert_equal staff.id, session[:user_id]
    assert_equal 'ppy', session[:auth_source]
    assert_redirected_to root_path
    get login_path, headers: { 'HTTP_PYORK_CYIN' => @student.sisid, 'HTTP_PYORK_USER' => staff.username }
    assert_nil session[:user_id]
    assert_not_equal 'ppy', session[:auth_source]
    assert_redirected_to invalid_login_path
  end

  test 'same email and callback supplied student id never link or create accounts' do
    mock_provider(email: @student.email)
    assert_no_difference(['User.count', 'GraduateIdentity.count']) do
      complete_oauth(params: { student_id: @student.id, mode: 'link' })
    end
    assert_nil session[:user_id]
    follow_redirect!
    assert_includes response.body, 'FGS'
    assert_not_includes response.body, @student.sisid
  end

  test 'external session cannot become PPY by visiting login without PPY headers' do
    ppy_login(@student)
    complete_oauth
    fresh_browser
    complete_oauth
    get login_path
    assert_not_equal 'ppy', session[:auth_source]
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
  end

  test 'external session cannot replace its connected Google account' do
    ppy_login(@student)
    complete_oauth
    fresh_browser
    complete_oauth
    mock_provider(uid: 'unlinked-replacement-subject')
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
    assert_equal 'stable-google-subject', @student.graduate_identities.find_by!(provider: 'google_oauth2').uid
  end

  test 'staff and impersonation cannot link identities' do
    staff = create(:user)
    ppy_login(staff)
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
    ppy_login(staff)
    get login_as_student_path(@student)
    assert_equal staff.id, session[:return_to_user_id]
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
  end

  test 'callback cannot overwrite provider or reassign another student identity' do
    ppy_login(@student)
    complete_oauth
    mock_provider(uid: 'different-google-subject')
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
    assert_equal 'stable-google-subject', @student.graduate_identities.first.uid
    other = create(:student)
    ppy_login(other)
    mock_provider
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
    assert_empty other.graduate_identities
  end

  test 'missing UID unverified Google claim and raw callback fail closed' do
    ppy_login(@student)
    mock_provider(uid: nil)
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
    mock_provider(email_verified: false)
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
    get graduate_auth_callback_path('google_oauth2'), params: { uid: 'forged', student_id: @student.id }
    assert_empty @student.graduate_identities
  end

  test 'Google requires a verified claim even when the provider email is absent' do
    ppy_login(@student)
    mock_provider(email_verified: nil)
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
    mock_provider(email: nil)
    assert_difference('GraduateIdentity.count', 1) { complete_oauth }
    assert_equal @student.id, session[:user_id]
  end

  test 'unknown provider unavailable and provider cancellation is actionable' do
    get graduate_auth_path('unknown')
    assert_response :not_found
    get graduate_auth_callback_path('unknown')
    assert_response :not_found
    OmniAuth.config.mock_auth[:google_oauth2] = :access_denied
    complete_oauth
    follow_redirect! while response.redirect?
    assert_includes response.body, 'try again'
    assert_nil session[:user_id]
  end

  test 'callbacks require a fresh matching server controlled intent' do
    ppy_login(@student)
    start_oauth
    travel 11.minutes do
      follow_redirect!
      assert_empty @student.graduate_identities
    end
    start_oauth
    get graduate_auth_callback_path('facebook')
    assert_empty @student.graduate_identities
    get graduate_auth_callback_path('google_oauth2')
    assert_empty @student.graduate_identities
  end

  test 'GET auth initiation and real middleware CSRF rejection' do
    get graduate_auth_path('google_oauth2')
    assert_response :not_found
    post graduate_auth_path('google_oauth2')
    assert_response :redirect
    assert_nil session[:graduate_oauth_intent]
    follow_redirect!
    assert_nil session[:user_id]
    get graduate_login_path
    post graduate_auth_path('google_oauth2'), params: { authenticity_token: 'invalid' }
    assert_response :redirect
    assert_nil session[:graduate_oauth_intent]
    get graduate_login_path
    assert_equal 'same-origin', response.headers['Referrer-Policy']
    post graduate_auth_path('google_oauth2'), params: { authenticity_token: csrf_token }, headers: { 'HTTP_ORIGIN' => 'null' }
    assert_response :redirect
    assert_nil session[:graduate_oauth_intent]
  end

  test 'real strategies reject missing or mismatched OAuth state without provider calls' do
    OmniAuth.config.test_mode = false
    %w[google_oauth2].each do |provider|
      start_oauth(provider)
      assert_response :redirect
      assert_not_includes response.location, '/callback'
      get graduate_auth_callback_path(provider), params: { code: 'test-code', state: 'forged-state' }
      assert_response :redirect
      assert_nil session[:user_id]
      assert_nil session[:graduate_oauth_intent]
      start_oauth(provider)
      get graduate_auth_callback_path(provider), params: { code: 'test-code' }
      assert_response :redirect
      assert_nil session[:user_id]
    end
  end

  test 'Google callback URL and authorization options cannot be overridden' do
    OmniAuth.config.test_mode = false
    start_oauth('google_oauth2', params: { redirect_uri: 'https://attacker.example/callback', access_type: 'offline', scope: 'dangerous', state: 'chosen' })
    query = CGI.parse(URI.parse(response.location).query)
    assert_equal [GraduateAuthentication.callback_url('google_oauth2')], query['redirect_uri']
    assert_equal ['online'], query['access_type']
    assert_equal %w[email openid profile], query['scope'].first.split.sort
    assert_not_equal ['chosen'], query['state']
  end

  test 'invitation GET does not consume and valid Google callback atomically enrolls' do
    invitation, url = invite(@student)
    assert_equal 48.hours, (invitation.expires_at - invitation.created_at).round.seconds
    assert_equal Digest::SHA256.hexdigest(CGI.parse(URI.parse(url).query)['token'].first), invitation.token_digest
    fresh_browser
    enter_invitation(url)
    assert_nil invitation.reload.consumed_at
    assert_difference('GraduateIdentity.count', 1) { complete_oauth }
    assert invitation.reload.consumed_at
    assert_equal @student.id, session[:user_id]
    assert_equal 'graduate_oauth', session[:auth_source]
  end

  test 'invalid expired reused and superseded invitations cannot authenticate' do
    invitation, url = invite(@student)
    fresh_browser
    get graduate_enroll_path, params: { token: 'bogus' }
    assert_response :unprocessable_entity
    travel 49.hours do
      get URI.parse(url).request_uri
      assert_response :unprocessable_entity
      assert_nil session[:user_id]
    end
    enter_invitation(url)
    complete_oauth
    fresh_browser
    get URI.parse(url).request_uri
    assert_response :unprocessable_entity
    first, old_url = invite(create(:student))
    invite(first.student)
    fresh_browser
    get URI.parse(old_url).request_uri
    assert_response :unprocessable_entity
    assert first.reload.revoked_at
  end

  test 'invitation conflicts and wrong provider leave token unconsumed' do
    ppy_login(@student)
    complete_oauth
    invitation, url = invite(create(:student))
    fresh_browser
    enter_invitation(url)
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
    assert_nil invitation.reload.consumed_at
    enter_invitation(url)
    assert_no_difference('GraduateIdentity.count') do
      get graduate_auth_callback_path('facebook'), params: { code: 'obsolete-code', state: 'obsolete-state' }
      assert_response :not_found
    end
    assert_nil invitation.reload.consumed_at
    assert_nil session[:user_id]
  end

  test 'invitation expiry during callback leaves token and identity unchanged' do
    invitation, url = invite(@student)
    fresh_browser
    enter_invitation(url)
    start_oauth
    invitation.update!(expires_at: 1.minute.ago)
    assert_no_difference('GraduateIdentity.count') { follow_redirect! }
    assert_nil invitation.reload.consumed_at
    assert_nil session[:user_id]
  end

  test 'invalid new token clears older enrollment intent' do
    _invitation, url = invite(@student)
    fresh_browser
    enter_invitation(url)
    get graduate_enroll_path, params: { token: 'invalid' }
    assert_response :unprocessable_entity
    assert_nil session[:graduate_enrollment]
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
  end

  test 'outstanding enrollment copied into two browsers can only consume once' do
    invitation, url = invite(@student)
    first = open_session
    second = open_session
    [first, second].each do |browser|
      browser.extend GraduateOAuthFlow
      browser.enter_invitation(url)
      browser.start_oauth
    end
    assert_difference('GraduateIdentity.count', 1) { first.follow_redirect! }
    assert_no_difference('GraduateIdentity.count') { second.follow_redirect! }
    assert_nil second.session[:user_id]
    assert invitation.reload.consumed_at
  end

  test 'staff missing confirmation and blocked target cannot create invitations' do
    staff = create(:user)
    ppy_login(staff)
    assert_no_difference('GraduateAuthenticationInvitation.count') do
      get staff_student_graduate_connections_path(@student)
      get graduate_login_path
      post student_graduate_invitations_path(@student), params: { provider: 'google_oauth2', identity_verified: '1', authenticity_token: csrf_token }
    end
    ppy_login(create(:user, role: User::MANAGER))
    get staff_student_graduate_connections_path(@student)
    assert_no_difference('GraduateAuthenticationInvitation.count') do
      post student_graduate_invitations_path(@student), params: { provider: 'google_oauth2', authenticity_token: csrf_token }
    end
    @student.update!(blocked: true)
    get staff_student_graduate_connections_path(@student)
    assert_no_difference('GraduateAuthenticationInvitation.count') do
      post student_graduate_invitations_path(@student), params: { provider: 'google_oauth2', identity_verified: '1', authenticity_token: csrf_token }
    end
  end

  test 'blocked PPY or linked student cannot login and later blocking clears access' do
    ppy_login(@student)
    complete_oauth
    fresh_browser
    @student.update!(blocked: true)
    get login_path, headers: { 'HTTP_PYORK_CYIN' => @student.sisid }
    assert_nil session[:user_id]
    complete_oauth
    assert_nil session[:user_id]
    @student.update!(blocked: false)
    complete_oauth
    @student.update!(blocked: true)
    get student_view_details_path
    assert_nil session[:user_id]
    assert_response :redirect
  end

  test 'blocked student at invitation callback cannot enroll' do
    invitation, url = invite(@student)
    fresh_browser
    enter_invitation(url)
    start_oauth
    @student.update!(blocked: true)
    assert_no_difference('GraduateIdentity.count') { follow_redirect! }
    assert_nil invitation.reload.consumed_at
  end

  test 'external logout clears session and Warden and PPY logout retains York redirect' do
    ppy_login(@student)
    complete_oauth
    get logout_path
    assert_redirected_to 'https://passportyork.yorku.ca/ppylogin/ppylogout'
    assert_nil session[:user_id]
    complete_oauth
    get logout_path
    assert_redirected_to graduate_login_path
    assert_nil session[:user_id]
    assert_nil session[:auth_source]
    assert_nil session[:graduate_identity_id]
    get student_view_details_path
    assert_response :redirect
  end

  test 'confirmed PPY unlink and FGS revoke end external sessions on subsequent request' do
    ppy_login(@student)
    complete_oauth
    identity = @student.graduate_identities.first
    get graduate_connections_path
    delete graduate_connection_path(identity), params: { authenticity_token: csrf_token }
    assert GraduateIdentity.exists?(identity.id)
    get graduate_connections_path
    delete graduate_connection_path(identity), params: { confirmation: '1', authenticity_token: csrf_token }
    assert_not GraduateIdentity.exists?(identity.id)
    complete_oauth
    fresh_browser
    complete_oauth
    identity = @student.graduate_identities.first
    manager_browser = open_session
    manager_browser.extend GraduateOAuthFlow
    manager_browser.ppy_login(create(:user, role: User::MANAGER))
    manager_browser.get staff_student_graduate_connections_path(@student)
    manager_browser.delete student_graduate_connection_path(@student, identity), params: {
      confirmation: '1', authenticity_token: manager_browser.csrf_token
    }
    assert_not GraduateIdentity.exists?(identity.id)
    get student_view_details_path
    assert_nil session[:user_id]
    assert_nil session[:graduate_identity_id]
  end

  test 'external user regular staff and impersonated student cannot revoke' do
    ppy_login(@student)
    complete_oauth
    identity = @student.graduate_identities.first
    fresh_browser
    complete_oauth
    get graduate_connections_path
    delete graduate_connection_path(identity), params: { confirmation: '1', authenticity_token: csrf_token }
    assert GraduateIdentity.exists?(identity.id)
    staff = create(:user)
    ppy_login(staff)
    get graduate_login_path
    delete student_graduate_connection_path(@student, identity), params: { confirmation: '1', authenticity_token: csrf_token }
    assert GraduateIdentity.exists?(identity.id)
    get login_as_student_path(@student)
    get graduate_connections_path
    delete graduate_connection_path(identity), params: { confirmation: '1', authenticity_token: csrf_token }
    assert GraduateIdentity.exists?(identity.id)
  end

  test 'foreign thesis id and staff actions remain rejected for external student' do
    ppy_login(@student)
    complete_oauth
    fresh_browser
    complete_oauth
    other = create(:student)
    foreign = create(:thesis, student: other)
    assert_raises(ActiveRecord::RecordNotFound) do
      get student_view_thesis_process_path(foreign, Thesis::PROCESS_BEGIN)
    end
    get new_user_path
    assert_redirected_to unauthorized_path
    get new_student_thesis_document_path(other, foreign)
    assert_redirected_to unauthorized_path
    get student_path(other)
    assert_redirected_to student_view_index_path
    get staff_student_graduate_connections_path(other)
    assert_redirected_to unauthorized_path
  end

  test 'database uniqueness and audits contain no tokens or UID secrets' do
    ppy_login(@student)
    complete_oauth
    identity = @student.graduate_identities.first
    assert_raises(ActiveRecord::RecordNotUnique) do
      GraduateIdentity.insert_all!([{ student_id: @student.id, provider: identity.provider, uid: 'different', created_at: Time.current, updated_at: Time.current }])
    end
    assert_raises(ActiveRecord::RecordNotUnique) do
      GraduateIdentity.insert_all!([{ student_id: create(:student).id, provider: identity.provider, uid: identity.uid, created_at: Time.current, updated_at: Time.current }])
    end
    invitation, url = invite(@student)
    raw_token = CGI.parse(URI.parse(url).query)['token'].first
    audits = Audited.audit_class.where(auditable_type: ['GraduateIdentity', 'GraduateAuthenticationInvitation'])
    assert audits.any?
    audit_text = audits.map(&:attributes).to_json
    %w[NEVER_STORE_ACCESS_TOKEN NEVER_STORE_REFRESH_TOKEN stable-google-subject].each { |secret| assert_not_includes audit_text, secret }
    assert_not_includes audit_text, raw_token
    assert_not_includes audit_text, invitation.token_digest
    assert_not_includes GraduateIdentity.column_names.join(','), 'token'
    get staff_student_graduate_connections_path(@student)
    delete student_graduate_connection_path(@student, identity), params: { confirmation: '1', authenticity_token: csrf_token }
    assert audits.where(action: 'destroy', auditable_type: 'GraduateIdentity').exists?
  end
end
