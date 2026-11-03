# frozen_string_literal: true

require_relative '../support/graduate_oauth_environment'
require 'test_helper'
require_relative '../support/graduate_oauth_flow'

# Policy (FGS, 2026-11-03): a Google account whose verified email is on
# exactly one active student record (primary or secondary) connects to that
# record on first sign-in. Google's subject is the key from then on.
class GraduateGoogleRecordMatchTest < ActionDispatch::IntegrationTest
  include GraduateOAuthFlow

  NOT_FOUND = 'We could not find a student record with this Google account’s email address.'

  setup do
    host! '127.0.0.1:3210'
    @student = create(:student)
    @student.update_columns(email: 'grad@yorku.ca', email_external: 'grad.personal@gmail.com')
    @forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    OmniAuth.config.test_mode = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
    Warden.test_reset!
  end

  def failure_page
    assert_redirected_to graduate_login_path
    follow_redirect!
    response.body
  end

  test 'verified_google_email_on_the_record_connects_and_signs_in' do
    mock_provider(uid: 'record-match-subject', email: 'Grad.Personal@Gmail.com')
    assert_difference('GraduateIdentity.count', 1) { complete_oauth }
    assert_redirected_to student_view_index_path
    identity = GraduateIdentity.last
    assert_equal [@student.id, 'record-match-subject', 'record_email', nil],
      [identity.student_id, identity.uid, identity.link_method, identity.linked_by_id]
    assert_equal @student.id, session[:user_id]

    fresh_browser
    @student.update_columns(email_external: 'changed@example.com')
    mock_provider(uid: 'record-match-subject', email: 'changed-at-google@example.com')
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
    assert_redirected_to student_view_index_path, 'Later sign-ins use the Google subject, not the email'
  end

  test 'primary_email_also_matches' do
    mock_provider(uid: 'primary-subject', email: 'grad@yorku.ca')
    complete_oauth
    assert_redirected_to student_view_index_path
    assert_equal @student.id, GraduateIdentity.find_by(uid: 'primary-subject').student_id
  end

  test 'unverified_unknown_shared_and_blocked_never_connect' do
    other = create(:student)
    other.update_columns(email_external: 'shared@gmail.com')
    create(:student).update_columns(email_external: 'shared@gmail.com')
    blocked = create(:student)
    blocked.update_columns(email_external: 'blocked@gmail.com', blocked: true)
    [['grad.personal@gmail.com', false], ['nobody@gmail.com', true], ['shared@gmail.com', true], ['blocked@gmail.com', true]].each do |email, verified|
      fresh_browser
      mock_provider(uid: "subject-#{email}", email: email, email_verified: verified)
      assert_no_difference(['GraduateIdentity.count', 'GraduateSession.count'], email) { complete_oauth }
      assert_nil session[:user_id]
      body = failure_page
      assert_not_includes body, @student.sisid
    end
  end

  test 'not_found_message_explains_passport_york_and_fgs' do
    mock_provider(uid: 'unknown-subject', email: 'nobody@gmail.com')
    complete_oauth
    body = failure_page
    assert_includes body, NOT_FOUND
    assert_includes body, 'If you are a current student, sign in with Passport York.'
    assert_includes body, 'contact the Faculty of Graduate Studies'
  end

  test 'a_record_already_connected_to_another_google_account_is_not_replaced' do
    @student.graduate_identities.create!(provider: 'google_oauth2', uid: 'original-subject', linked_by: @student, link_method: 'ppy')
    mock_provider(uid: 'second-subject', email: 'grad.personal@gmail.com')
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
    assert_nil session[:user_id]
    assert_redirected_to graduate_login_path
  end

  test 'posted_student_id_and_mode_are_ignored' do
    other = create(:student)
    mock_provider(uid: 'param-subject', email: 'grad.personal@gmail.com')
    complete_oauth(params: { student_id: other.id, mode: 'link' })
    assert_equal @student.id, GraduateIdentity.find_by(uid: 'param-subject').student_id
    assert_empty other.graduate_identities
  end
end
