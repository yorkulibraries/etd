# frozen_string_literal: true

# Failure scenarios/specification written before the controller superclass edits:
# - PPY and external Students reach staff report/dashboard/status/review pages,
#   account lists, student lists, audit trails, searches, or management actions.
# - Existing STI class-read permissions accidentally disclose another student.
# - Blocking these pages accidentally breaks the Student show redirect or /my.
# - The new guard broadens regular staff privileges or denies existing manager
#   and staff permissions. Ordinary staff retain existing class permissions
#   while custom actions remain subject to the existing CanCan rules.
# Request-flow E2E: establish genuine PPY or mocked linked OAuth sessions, issue
# real requests to every boundary, assert denial before foreign data is rendered,
# exercise manager/staff existing permissions and verify own /my/thesis access.

require 'test_helper'
require_relative '../support/graduate_oauth_flow'

class GraduateStaffBoundariesTest < ActionDispatch::IntegrationTest
  include GraduateOAuthFlow

  setup do
    host! '127.0.0.1:3210'
    @student = create(:student, name: 'Boundary Owner Graduate')
    @own_thesis = create(:thesis, student: @student, title: 'Boundary Own Thesis')
    @other = create(:student, name: 'Foreign Student Private Marker')
    @foreign = create(:thesis, student: @other, title: 'Foreign Thesis Private Marker', status: Thesis::UNDER_REVIEW)
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

  test 'external Student cannot read staff pages and retains own student flow' do
    ppy_login(@student)
    complete_oauth
    fresh_browser
    complete_oauth
    assert_equal 'graduate_oauth', session[:auth_source]
    assert_student_boundaries
    assert_own_flow
  end

  test 'PPY Student cannot read staff pages and retains own student flow' do
    ppy_login(@student)
    assert_student_boundaries
    assert_own_flow
  end

  test 'manager keeps reports users and student read search audit permissions' do
    ppy_login(create(:user, role: User::MANAGER))
    assert_staff_reports
    [users_path, blocked_users_path, students_path, audit_trail_student_path(@other)].each do |path|
      get path
      assert_response :success, path
    end
    get gem_search_students_path, params: { sisid: @other.sisid }
    assert_redirected_to student_path(@other)
  end

  test 'regular staff retains reports lists audits and existing custom action denials' do
    ppy_login(create(:user, role: User::STAFF))
    assert_staff_reports
    [students_path, audit_trail_student_path(@other), users_path].each do |path|
      get path
      assert_response :success, path
    end
    get blocked_users_path
    assert_redirected_to unauthorized_path
    get gem_search_students_path, params: { sisid: @other.sisid }
    assert_redirected_to unauthorized_path
  end

  private

  def assert_student_boundaries
    paths = [reports_dashboard_path, reports_by_status_path(status: Thesis::UNDER_REVIEW),
             reports_review_thesis_path(id: @foreign.id), users_path, blocked_users_path,
             students_path, audit_trail_student_path(@other), gem_search_students_path(sisid: @other.sisid)]
    paths.each do |path|
      get path
      assert_redirected_to unauthorized_path, path
      assert_not_includes response.body, @other.name
      assert_not_includes response.body, @foreign.title
    end
    # Preserve the explicit Student show redirect, even for a foreign ID.
    get student_path(@other)
    assert_redirected_to student_view_index_path
    get edit_student_path(@other)
    assert_redirected_to unauthorized_path
    get graduate_login_path
    assert_no_difference('Student.count') do
      post students_path, params: { authenticity_token: csrf_token, student: { name: 'Rejected New Student' } }
    end
    assert_redirected_to unauthorized_path
  end

  def assert_own_flow
    get student_view_details_path
    assert_response :success
    assert_includes response.body, @student.name
    get student_view_thesis_process_path(@own_thesis, Thesis::PROCESS_BEGIN)
    assert_response :success
    assert_includes response.body, @own_thesis.title
    assert_equal @student.id, session[:user_id]
  end

  def assert_staff_reports
    get reports_dashboard_path
    assert_response :success
    get reports_by_status_path, params: { status: Thesis::UNDER_REVIEW }
    assert_response :success
    get reports_review_thesis_path, params: { id: @foreign.id }
    assert_response :success
    assert_includes response.body, @foreign.title
  end
end
