# frozen_string_literal: true
require_relative '../support/graduate_email_browser_case'

class GraduateEmailManagementTest < GraduateEmailBrowserCase
  test 'initial_management_requires_recipient_confirmation_and_identity_checkbox' do
    browser_ppy_login(@actor)
    visit staff_student_graduate_connections_path(@student)
    assert_selector 'h2', text: 'Approve email sign-in'
    assert_required_checkbox 'email_identity_verified'
    fill_in 'Approved sign-in address', with: 'approved@example.com'
    fill_in 'Confirm approved address', with: 'different@example.com'
    check 'email_identity_verified'
    click_button 'Create email invitation'
    assert_current_path staff_student_graduate_connections_path(@student)
    assert_text 'Confirm one supported address and complete the FGS identity check'
    assert_selector 'h2', text: 'Approve email sign-in'
    assert_equal 0, GraduateEmailApproval.uncached { GraduateEmailApproval.count }
    fill_in 'Approved sign-in address', with: 'approved@example.com'
    fill_in 'Confirm approved address', with: 'APPROVED@example.com'
    check 'email_identity_verified'
    click_button 'Create email invitation'
    assert_selector 'h1', text: 'Share this invitation once'
    assert_equal 1, GraduateEmailApproval.uncached { GraduateEmailApproval.count }
    assert_equal 0, Delayed::Job.where(queue: GraduateEmail::Limits::QUEUE).count
  end

  test 'staff_without_management_permission_cannot_approve' do
    @actor.update!(role: User::STAFF)
    browser_ppy_login(@actor)
    visit staff_student_graduate_connections_path(@student)
    assert_current_path unauthorized_path
    assert_equal 0, GraduateEmailApproval.count
  end
end
