# frozen_string_literal: true
require_relative '../support/graduate_email_browser_case'

class GraduateEmailAuthenticationTest < GraduateEmailBrowserCase
  test 'fgs_confirms_one_address_and_enrollment_requires_mailbox_code' do
    approval, token = issue_approval
    browser_ppy_login(@actor)
    visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
    assert_current_path '/graduate/email/verify'
    assert_equal 0, GraduateSession.where(authentication_method: 'email').count
    assert_nil approval.reload.consumed_at
    assert_no_selector 'input[name="address"]'
    resend_code
    row, code = run_mail_worker
    assert_equal approval.id, row.approval_id
    enter_code(code)
    assert_current_path student_view_index_path
    assert_equal @student.id, GraduateEmailActiveAddress.first.student_id
    assert approval.reload.consumed_at
  end

  test 'returning_graduate_opens_existing_student_record' do
    enrolled_connection
    thesis = create(:thesis, student: @student)
    before = [Student.count, @student.email]
    request_login
    _, code = run_mail_worker
    enter_code(code)
    assert_current_path student_view_thesis_process_path(thesis, Thesis::PROCESS_BEGIN)
    assert_selector 'main'
    visit student_view_details_path
    assert_text @student.name
    assert_equal before, [Student.count, @student.reload.email]
    visit student_view_thesis_process_path(thesis, Thesis::PROCESS_BEGIN)
    assert_current_path student_view_thesis_process_path(thesis, Thesis::PROCESS_BEGIN)
  end

  test 'unknown_blocked_unenrolled_and_throttled_look_identical' do
    enrolled_connection
    structures = []
    ['approved@example.com', 'unknown@example.com', 'unenrolled@example.com', 'approved@example.com'].each do |address|
      request_login(address)
      assert_generic_form
      structures << page.all('main form').map { |form| [form[:action], form.all('input', visible: :all).map { |field| [field[:name], field[:type]] }] }
      browser_fresh_session
    end
    @student.block
    request_login
    assert_generic_form
    structures << page.all('main form').map { |form| [form[:action], form.all('input', visible: :all).map { |field| [field[:name], field[:type]] }] }
    assert structures.all? { |shape| shape == structures.first }, 'generic forms match'
  end

  test 'six_digit_wrong_expired_reused_and_cross_purpose_codes_fail' do
    enrolled_connection
    request_login
    row, code = run_mail_worker
    5.times do
      enter_code('00000x')
      assert_text 'The code is incorrect or has expired. Request a new code and try again.'
    end
    enter_code(code)
    assert_current_path '/graduate/email/verify'
    assert_equal 5, row.reload.failed_attempts
    travel_to row.expires_at
    enter_code(code)
    assert_current_path '/graduate/email/verify'
  end

  test 'two_browsers_resend_without_interference' do
    enrolled_connection
    request_login
    first, first_code = run_mail_worker
    Capybara.using_session(:second) do
      travel 61.seconds
      request_login
      second, second_code = run_mail_worker
      enter_code(first_code)
      assert_current_path '/graduate/email/verify'
      enter_code(second_code)
      assert_current_path student_view_index_path
      assert_equal 'sent', first.reload.state
      assert second.reload.consumed_at
    end
    enter_code(first_code)
    assert_current_path student_view_index_path
  end

  test 'send_limit_does_not_prevent_valid_verification' do
    enrolled_connection
    SecureRandom.stub(:random_number, 7) do
      request_login
      row, code = run_mail_worker
      assert code == '000007', 'leading-zero code retained in RAM'
      resend_code
      assert_equal 'sent', row.reload.state
      enter_code(code)
      assert_current_path student_view_index_path
    end
  end

  test 'email_only_login_redirect_works' do
    GraduateAuthentication.stub(:enabled_providers, []) do
      visit student_view_details_path
      assert_current_path graduate_login_path
      assert_link 'Email me a sign-in code'
      assert_link 'Sign in with Passport York'
      click_link 'Email me a sign-in code'
      assert_current_path '/graduate/email'
    end
  end
  test 'fresh_code_expires_at_exact_five_minutes_in_the_browser' do
    travel_to Time.current.change(usec: 0)
    enrolled_connection
    request_login
    row, code = run_mail_worker
    travel_to row.expires_at
    enter_code(code)
    assert_selector '#code-error', text: 'The code is incorrect or has expired'
    assert_current_path '/graduate/email/verify'
    assert_equal 0, GraduateSession.where(authentication_method: 'email').count
  end

  test 'expired_forty_eight_hour_invitation_never_enrolls_from_browser' do
    travel_to Time.current.change(usec: 0)
    approval, token = issue_approval
    travel_to approval.expires_at
    visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
    assert_current_path '/graduate/email/verify'
    assert_generic_form
    resend_code
    assert_equal 0, GraduateEmailChallenge.where.not(student_id: nil).count
    assert_nil approval.reload.consumed_at
    visit student_view_index_path
    assert_current_path graduate_login_path
  end

  test 'enrollment_code_cannot_sign_in_as_login_and_success_cannot_replay' do
    approval, token = issue_approval
    visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
    assert_current_path '/graduate/email/verify'
    resend_code
    _, old_code = run_mail_worker
    click_link 'Use another email address'
    assert_current_path '/graduate/email'
    request_login
    enter_code(old_code)
    assert_selector '#code-error', text: 'The code is incorrect or has expired'
    assert_nil approval.reload.consumed_at
    assert_equal 0, GraduateSession.where(authentication_method: 'email').count
    travel 61.seconds
    visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
    assert_current_path '/graduate/email/verify'
    resend_code
    _, code = run_mail_worker
    enter_code(code)
    assert_current_path student_view_index_path
    assert approval.reload.consumed_at
    visit '/graduate/email/verify'
    enter_code(code)
    assert_selector '#code-error', text: 'The code is incorrect or has expired'
    assert_equal 1, GraduateSession.uncached { GraduateSession.where(authentication_method: 'email').count }
  end

end
