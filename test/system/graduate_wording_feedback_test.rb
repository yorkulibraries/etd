# frozen_string_literal: true
require_relative '../support/graduate_email_browser_case'

# Checks the November 2026 wording feedback on the staff connections page, the
# student's own connections page and the email sign-in page.
# Screenshots: tmp/wording-feedback/*.png
class GraduateWordingFeedbackTest < GraduateEmailBrowserCase
  YORKU = 'wording.student@yorku.ca'
  PERSONAL = 'wording.student@example.com'
  DIR = Rails.root.join('tmp/wording-feedback')

  setup do
    @student.update_columns(email: YORKU, email_external: PERSONAL)
  end

  def link_google
    GraduateIdentity.create!(student: @student, linked_by: @student, provider: 'google_oauth2',
                             uid: 'wording-google', link_method: 'record_email')
  end

  def shot(name, height: 2600)
    FileUtils.mkdir_p(DIR)
    current_window.resize_to(1440, height)
    page.save_screenshot(DIR.join("#{name}.png").to_s)
  ensure
    current_window.resize_to(1440, 1000)
  end

  def connect_record_address(address)
    GraduateEmailConnection.create!(student: @student, source: 'record', normalized_address: address,
                                    verified_at: Time.current)
  end

  test 'staff page uses the new wording and hides the single-provider dropdown' do
    connect_record_address(YORKU)
    browser_ppy_login(@actor)
    visit staff_student_graduate_connections_path(@student)

    # The invitation box shows while no Google account is connected.
    assert_selector 'h2', text: 'Create an invitation for a student to connect a secondary email address'
    assert_text 'first verify their identity through an approved Faculty of Graduate Studies (FGS) process outside of the ETD system.'
    assert_text 'on their own after logging into their Google account in the same browser.'
    assert_text 'Only use an invitation if the Google email is not on their FGS account'
    assert_no_selector 'select#provider'
    assert_no_text 'Account provider'
    assert_text 'I verified this student’s identity via an approved FGS process outside of the ETD system.'

    link_google
    visit staff_student_graduate_connections_path(@student)
    assert_selector 'h3', text: 'Google account'
    assert_text "Google account linked by student on #{Date.current.strftime('%B %-d, %Y')}."
    assert_text 'I confirm removal of this Google account connection.'

    # The connected address is the YorkU one, so the sentence must not call it non-YorkU.
    assert_text 'Connected using the YorkU email address on the student record.'
    assert_selector 'h2', text: 'Replace or recover a secondary non-YorkU email sign-in'
    assert_selector '[data-record-addresses] li', count: 2
    assert_selector '[data-record-addresses] li', text: "YorkU email: #{YORKU}"
    assert_selector '[data-record-addresses] li', text: "Alternate (non-YorkU) email: #{PERSONAL}"
    assert_text 'Check this box to remove this student’s email sign-in connection, pending invitations and email sessions.'
    shot('staff-connections')
  end

  test 'a non-YorkU record address is described as secondary non-YorkU, and the student sees your' do
    link_google
    connect_record_address(PERSONAL)
    browser_ppy_login(@actor)
    visit staff_student_graduate_connections_path(@student)
    assert_text 'Connected using a secondary non-YorkU email address on the student record.'
    browser_fresh_session

    browser_ppy_login(@student)
    visit graduate_connections_path
    assert_selector 'h3', text: 'Google account'
    assert_text 'Google account linked by student on'
    assert_text 'Connected using a secondary non-YorkU email address on your student record.'
    shot('student-connections', height: 1400)
  end

  test 'email sign-in page help text' do
    browser_fresh_session
    visit graduate_email_path
    assert_text 'If a non-YorkU email address is not on your student record or you have lost access to the ' \
                'non-YorkU email affiliated with your student record, contact the Faculty of Graduate Studies’ ' \
                'Graduate Student Affairs team to update your record.'
    assert_no_text 'usual support channel'
    shot('email-sign-in', height: 1000)
  end
end
