# frozen_string_literal: true
require_relative '../support/graduate_email_browser_case'

# Staff could not see a student's alternate (non-YorkU) email on the student
# page, and an approved email sign-in address never showed under "Alternate
# (non-YorkU) email" on the connections page.
# Ways this could go wrong, checked below:
# - the student page has no "Alternate (non-YorkU) email" at all
# - an empty alternate email shows as a blank line instead of saying so
# - the approved sign-in address is missing from either page
# - more than one alternate email is listed (record address and sign-in address)
# - a removed (revoked) sign-in address still shows
# - staff who cannot manage sign-in (role "staff") see the sign-in address
# - the Google email is shown even though ETD never stores it
# Screenshots: tmp/graduate-alternate-email-display/*.png
class GraduateAlternateEmailDisplayTest < GraduateEmailBrowserCase
  DIR = Rails.root.join('tmp/graduate-alternate-email-display')
  SIGN_IN_NOTE = 'used for email sign-in'

  def shot(name)
    FileUtils.mkdir_p(DIR)
    current_window.resize_to(1440, 1600)
    page.save_screenshot(DIR.join("#{name}.png").to_s)
  ensure
    current_window.resize_to(1440, 1000)
  end

  def alternate_on_student_page
    find('[data-alternate-email]').text.squish
  end

  def alternate_on_connections_page
    find('[data-record-addresses] li', text: 'Alternate (non-YorkU) email').text.squish
  end

  test 'alternate email and approved sign-in address show on the student and connections pages' do
    @student.update_columns(email_external: nil)
    browser_ppy_login(@actor)

    # Nothing on record and no sign-in address.
    visit student_path(@student)
    assert_text 'Alternate (non-YorkU) email'
    assert_equal 'None on the student record', alternate_on_student_page
    shot('1-student-page-none')

    # An address on the record shows on both pages.
    @student.update_columns(email_external: 'record.alt@example.com')
    visit student_path(@student)
    assert_equal 'record.alt@example.com', alternate_on_student_page
    visit staff_student_graduate_connections_path(@student)
    assert_equal 'Alternate (non-YorkU) email: record.alt@example.com', alternate_on_connections_page

    # The record address is also the sign-in address: listed once.
    record_conn = GraduateEmailConnection.create!(student: @student, source: 'record',
                                                  normalized_address: 'record.alt@example.com', verified_at: Time.current)
    visit student_path(@student)
    assert_equal 'record.alt@example.com (used for email sign-in)', alternate_on_student_page
    visit staff_student_graduate_connections_path(@student)
    assert_equal 'Alternate (non-YorkU) email: record.alt@example.com (used for email sign-in)',
                 alternate_on_connections_page
    record_conn.update_columns(revoked_at: Time.current)

    # A staff-approved address that is not on the record.
    GraduateEmailConnection.create!(student: @student, source: 'staff', approved_by: @actor,
                                    normalized_address: 'approved.signin@example.com', verified_at: Time.current)
    GraduateIdentity.create!(student: @student, linked_by: @student, provider: 'google_oauth2',
                             uid: 'alt-display-google', link_method: 'record_email')
    visit student_path(@student)
    assert_equal "approved.signin@example.com (#{SIGN_IN_NOTE})", alternate_on_student_page
    assert_text 'Google account connected on'
    assert_no_text 'does not keep the Google email'
    assert_no_text 'record.alt@example.com'
    shot('2-student-page-record-and-approved')
    visit staff_student_graduate_connections_path(@student)
    assert_equal "Alternate (non-YorkU) email: approved.signin@example.com (#{SIGN_IN_NOTE})",
                 alternate_on_connections_page
    shot('3-connections-page-record-and-approved')

    # Removed sign-in address no longer shows.
    GraduateEmailConnection.where(student: @student).update_all(revoked_at: Time.current)
    visit student_path(@student)
    assert_equal 'record.alt@example.com', alternate_on_student_page
    visit staff_student_graduate_connections_path(@student)
    assert_equal 'Alternate (non-YorkU) email: record.alt@example.com', alternate_on_connections_page
  end

  test 'staff without sign-in access see the record email but not the sign-in address' do
    @student.update_columns(email_external: 'record.alt@example.com')
    GraduateEmailConnection.create!(student: @student, source: 'staff', approved_by: @actor,
                                    normalized_address: 'approved.signin@example.com', verified_at: Time.current)
    staff = create(:user, role: User::STAFF)
    browser_ppy_login(staff)
    visit student_path(@student)
    assert_equal 'record.alt@example.com', alternate_on_student_page
    assert_no_text 'approved.signin@example.com'
    shot('4-plain-staff-student-page')
  end
end
