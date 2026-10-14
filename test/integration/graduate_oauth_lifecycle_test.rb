# frozen_string_literal: true

# Written before the review corrections: dormant graduate sessions must stay
# revoked after block/unblock; failed invitation-session issuance must roll back
# enrollment; expired graduate logout must retain its public destination.
require 'test_helper'
require_relative '../support/graduate_oauth_flow'

class GraduateOAuthLifecycleTest < ActionDispatch::IntegrationTest
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

  test 'blocking through staff route revokes all dormant graduate browsers' do
    first = cookies[Rails.application.config.session_options[:key]].dup
    fresh_browser
    complete_oauth
    second = cookies[Rails.application.config.session_options[:key]].dup
    assert_equal 2, GraduateSession.where(revoked_at: nil).count
    fresh_browser
    ppy_login(create(:user, role: User::MANAGER))
    get graduate_login_path
    post block_student_path(@student), params: { authenticity_token: csrf_token }
    assert @student.reload.blocked?
    get graduate_login_path
    post unblock_student_path(@student), params: { authenticity_token: csrf_token }
    assert_not @student.reload.blocked?
    assert_equal 0, GraduateSession.where(revoked_at: nil).count
    [first, second].each do |saved|
      cookies[Rails.application.config.session_options[:key]] = saved
      get student_view_details_path
      assert_redirected_to login_path
      assert_nil session[:user_id]
    end
  end

  test 'invitation enrollment rolls back if graduate session issuance fails' do
    target = create(:student)
    invitation, url = invite(target)
    fresh_browser
    enter_invitation(url)
    GraduateSession.stubs(:issue!).raises(ActiveRecord::RecordInvalid.new(GraduateSession.new))
    assert_no_difference('GraduateIdentity.count') { complete_oauth }
    assert_nil invitation.reload.consumed_at
    assert invitation.usable?
    assert_nil session[:user_id]
  end

  test 'expired graduate logout keeps public destination without PPY logout' do
    travel 13.hours do
      get logout_path
      assert_redirected_to graduate_login_path
      assert_nil session[:user_id]
      assert_nil session[:graduate_session_token]
    end
  end
end
