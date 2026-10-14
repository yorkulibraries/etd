# frozen_string_literal: true

# Failure scenarios and request specification were written before the correction:
# active staff support access to blocked GEM Students breaks; legacy staff
# cookies lack auth_source; revoked return actors retain support access; invalid
# actors/targets bypass the guard; blocked real Students or external sessions gain
# sign-in/linking privileges. These are real Rails request flows. Only provider
# success is mocked; legacy fixtures are encrypted with Rails' own cookie jar.
require 'test_helper'
require_relative '../support/graduate_oauth_flow'

class GraduateImpersonationTest < ActionDispatch::IntegrationTest
  include GraduateOAuthFlow

  setup do
    host! '127.0.0.1:3210'
    @student = create(:student, blocked: true, name: 'Blocked Support Student')
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

  test 'active admin manager and staff support blocked Students without OAuth linking' do
    [User::ADMIN, User::MANAGER, User::STAFF].each do |role|
      fresh_browser
      actor = create(:user, role: role)
      ppy_login(actor)
      assert_support_flow(actor, source: 'ppy')
    end
  end

  test 'legacy signed staff sessions without source retain blocked Student support' do
    [User::ADMIN, User::MANAGER, User::STAFF].each do |role|
      fresh_browser
      actor = create(:user, role: role)
      ppy_login(actor)
      replace_signed_session(session.to_hash.except('auth_source'))
      assert_support_flow(actor, source: nil)
    end
  end

  test 'blocked or deleted return actors revoke support access on the next request' do
    [true, false].each do |target_blocked|
      @student.update!(blocked: target_blocked)
      %i[blocked deleted].each do |revocation|
        fresh_browser
        actor = create(:user, role: User::ADMIN)
        ppy_login(actor)
        get login_as_student_path(@student)
        assert_equal actor.id, session[:return_to_user_id]
        get student_view_details_path
        assert_response :success
        revocation == :blocked ? actor.update!(blocked: true) : actor.destroy!
        assert_session_revoked
      end
    end
  end

  test 'impersonation requires an active staff return actor and a Student target' do
    actor = create(:user, role: User::ADMIN)
    other_student = create(:student)
    [
      { user_id: @student.id, return_to_user_id: other_student.id },
      { user_id: actor.id, return_to_user_id: actor.id },
      { user_id: @student.id, return_to_user_id: actor.id, auth_source: 'graduate_oauth' },
      { user_id: @student.id, return_to_user_id: 999_999_999 }
    ].each do |fixture|
      fresh_browser
      ppy_login(actor)
      replace_signed_session(session.to_hash.merge(fixture.stringify_keys))
      assert_session_revoked
    end
    fresh_browser
    ppy_login(actor)
    get login_as_student_path(@student)
    actor.update!(role: User::STUDENT)
    assert_session_revoked
  end

  test 'blocked real Students remain denied and external Students cannot impersonate' do
    @student.update!(blocked: false)
    ppy_login(@student)
    complete_oauth
    fresh_browser
    @student.update!(blocked: true)
    get login_path, headers: { 'HTTP_PYORK_CYIN' => @student.sisid, 'HTTP_PYORK_USER' => @student.username }
    assert_redirected_to invalid_login_path
    assert_nil session[:user_id]
    complete_oauth
    assert_nil session[:user_id]
    @student.update!(blocked: false)
    complete_oauth
    assert_equal 'graduate_oauth', session[:auth_source]
    other = create(:student)
    get login_as_student_path(other)
    assert_redirected_to unauthorized_path
    assert_nil session[:return_to_user_id]
    assert_equal @student.id, session[:user_id]
  end

  private

  def assert_support_flow(actor, source:)
    get login_as_student_path(@student)
    assert_redirected_to student_view_index_path
    assert_equal @student.id, session[:user_id]
    assert_equal actor.id, session[:return_to_user_id]
    get student_view_details_path
    assert_response :success
    assert_includes response.body, @student.name
    source.nil? ? assert_nil(session[:auth_source]) : assert_equal(source, session[:auth_source])
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
    assert_nil session[:graduate_oauth_intent]
    assert_equal actor.id, session[:return_to_user_id]
    assert_equal @student.id, session[:user_id]
    get logout_as_student_path
    assert_redirected_to student_path(@student)
    assert_equal actor.id, session[:user_id]
    assert_nil session[:return_to_user_id]
    get student_path(@student)
    assert_response :success
    assert_includes response.body, 'Login as this student'
  end

  def assert_session_revoked
    get student_view_details_path
    assert_redirected_to graduate_login_path
    assert_nil session[:user_id]
    assert_nil session[:return_to_user_id]
    assert_nil session[:auth_source]
    assert_nil session[:graduate_identity_id]
    assert_not_includes response.body, @student.name
  end

  # Construct a pre-existing, server-signed cookie without adding an application
  # route or shortcut. The following request uses the full ordinary Rails stack.
  def replace_signed_session(attributes)
    key = Rails.application.config.session_options[:key]
    jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
    jar.signed_or_encrypted[key] = { value: attributes }
    headers = {}
    jar.write(headers)
    cookies.merge(headers['Set-Cookie'], URI.parse('http://127.0.0.1:3210/'))
    assert_equal attributes['user_id'], jar.signed_or_encrypted[key]['user_id']
  end
end
