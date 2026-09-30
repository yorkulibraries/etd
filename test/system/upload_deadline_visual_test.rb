# frozen_string_literal: true

require 'application_system_test_case'

class UploadDeadlineVisualTest < ApplicationSystemTestCase
  setup do
    FileUtils.mkdir_p(Rails.root.join('tmp/test-screenshots'))

    @student = create(:student, name: 'Upload Demo Student')
    @open_thesis = create(:thesis, student: @student, title: 'Open Upload Window Thesis', status: Thesis::OPEN)
    @expired_thesis = create(:thesis, student: @student, title: 'Expired Upload Window Thesis', status: Thesis::OPEN)

    @open_thesis.invitations.create!(
      student: @student,
      sent_at: Time.utc(2026, 9, 1, 14),
      expires_at: Time.utc(2026, 9, 15, 3, 59, 59),
      upload_expires_at: Time.utc(2026, 10, 31, 3, 59, 59),
      accepted_at: Time.utc(2026, 9, 2, 15)
    )
    @expired_thesis.invitations.create!(
      student: @student,
      sent_at: 20.days.ago,
      expires_at: 10.days.ago.end_of_day,
      upload_expires_at: 1.day.ago.end_of_day,
      accepted_at: 15.days.ago
    )
  end

  test 'student list and upload pages show open and expired upload deadlines' do
    login_as(@student)
    visit student_view_index_path

    assert_selector 'a', text: 'Open Upload Window Thesis'
    assert_selector '.invitation-expired', text: /Expired Upload Window Thesis/
    assert_selector '.invitation-expired', text: /Upload deadline passed—contact ETD staff/
    page.save_screenshot(Rails.root.join('tmp/test-screenshots/upload-deadline-student-list.png'))

    visit student_view_thesis_process_path(@open_thesis, Thesis::PROCESS_UPLOAD)
    assert_selector '.upload-deadline', text: /Upload by October 30, 2026/
    page.save_screenshot(Rails.root.join('tmp/test-screenshots/upload-deadline-open-upload-page.png'))

    visit student_view_thesis_process_path(@expired_thesis, Thesis::PROCESS_BEGIN)
    assert_text 'Upload deadline passed—contact ETD staff'
    page.save_screenshot(Rails.root.join('tmp/test-screenshots/upload-deadline-expired-block.png'))
  end

  test 'staff student page shows invitation and upload deadlines' do
    admin = create(:user, role: User::ADMIN, username: 'upload_deadline_admin')
    sign_in_via_passport(admin)
    visit student_path(@student)

    assert_current_path student_path(@student)
    assert_text 'Upload Demo Student'
    assert_selector '.invitation-deadline', text: /Invitation opened/
    assert_selector '.upload-deadline', text: /Upload by October 30, 2026/
    assert_selector '.upload-deadline', text: /Upload deadline passed/
    page.save_screenshot(Rails.root.join('tmp/test-screenshots/upload-deadline-staff-student-show.png'))
  end

  private

  def sign_in_via_passport(user)
    headers = {
      'PYORK_USER' => user.username,
      'PYORK_CYIN' => user.sisid.presence || user.username,
      'PYORK_EMAIL' => user.email,
      'PYORK_TYPE' => user.role,
      'PYORK_FIRSTNAME' => user.name.to_s.split.first,
      'PYORK_SURNAME' => user.name.to_s.split.last
    }
    browser = page.driver.browser
    if browser.respond_to?(:execute_cdp)
      browser.execute_cdp('Network.enable')
      browser.execute_cdp('Network.setExtraHTTPHeaders', headers:)
    end
    visit login_path
    assert_no_current_path invalid_login_path, wait: 10
  end
end
