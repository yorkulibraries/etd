# frozen_string_literal: true
require_relative '../support/graduate_email_browser_case'

# Proves the per-ETD invitation deadline applies to graduates who sign in with
# an email code or Google, not only Passport York. Screenshots are written to
# tmp/graduate-authentication/screenshots/deadline-*.png.
class ThesisDeadlineGraduateSignInTest < GraduateEmailBrowserCase
  RECORD_ADDRESS = 'graduate.personal@example.com'

  setup do
    @student.update_columns(email_external: RECORD_ADDRESS)
    @thesis = create(:thesis, student: @student, title: 'Deadline Test Thesis')
  end

  EVIDENCE = Rails.root.join('tmp/deadline-evidence')

  # Own screenshots: the shared harness disables browser_artifact on purpose.
  # Never called on a page that shows a sign-in code.
  def shot(name)
    FileUtils.mkdir_p(EVIDENCE)
    page.save_screenshot(EVIDENCE.join("#{name}.png").to_s)
    File.write(EVIDENCE.join("#{name}.txt"), "#{page.current_path}\n\n#{page.text}")
  end

  def expired_invitation!
    ThesisInvitation.create!(student: @student, thesis: @thesis,
      sent_at: 20.days.ago, expires_at: 6.days.ago)
  end

  def open_invitation!
    ThesisInvitation.create!(student: @student, thesis: @thesis,
      sent_at: 1.day.ago, expires_at: 13.days.from_now)
  end

  def email_code_sign_in(shot_prefix)
    request_login(RECORD_ADDRESS)
    _, code = run_mail_worker
    enter_code(code)
    assert_no_current_path '/graduate/email/verify'
    shot("#{shot_prefix}-after-sign-in")
  end

  teardown do
    OmniAuth.config.test_mode = @previous_test_mode unless @previous_test_mode.nil?
    OmniAuth.config.mock_auth.clear
  end

  # Simulated Google: the real callback, record matching and session code run,
  # only Google's own servers are replaced by a test reply.
  def google_sign_in(shot_prefix)
    @previous_test_mode = OmniAuth.config.test_mode
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: 'google_oauth2', uid: 'deadline-google-subject', info: { email: RECORD_ADDRESS },
      extra: { raw_info: { 'email_verified' => true } }
    )
    visit graduate_login_path
    click_button 'Continue with Google'
    assert_no_current_path graduate_login_path
    shot("#{shot_prefix}-after-sign-in")
  end

  def assert_thesis_blocked(name)
    visit student_view_thesis_process_path(@thesis, Thesis::PROCESS_BEGIN)
    shot(name)
    assert_text 'Invitation expired'
    refute @thesis.reload.invitation_accessible?
    assert_nil @thesis.invitations.last.accepted_at
  end

  test 'email code sign-in after the deadline cannot open the thesis' do
    expired_invitation!
    email_code_sign_in('deadline-email-expired')
    assert_thesis_blocked('deadline-email-expired-thesis-blocked')
  end

  test 'google sign-in after the deadline cannot open the thesis' do
    expired_invitation!
    google_sign_in('deadline-google-expired')
    assert_thesis_blocked('deadline-google-expired-thesis-blocked')
  end

  test 'email code sign-in before the deadline opens the thesis and accepts the invitation' do
    invitation = open_invitation!
    email_code_sign_in('deadline-email-open')
    visit student_view_thesis_process_path(@thesis, Thesis::PROCESS_BEGIN)
    assert_no_text 'Invitation expired'
    shot('deadline-email-open-thesis-opens')
    assert invitation.reload.accepted_at
  end
end
