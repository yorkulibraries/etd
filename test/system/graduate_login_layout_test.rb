# frozen_string_literal: true
require_relative '../support/graduate_email_browser_case'

# The public sign-in page lists Passport York first (current students), then the
# graduate options: Google, then an email code. Screenshot: tmp/login-layout/.
class GraduateLoginLayoutTest < GraduateEmailBrowserCase
  test 'passport york comes first, then the graduate options' do
    visit graduate_login_path
    main = find('main')
    text = main.text
    assert_selector 'h1', text: 'Graduate Student Sign-In'
    ppy_intro = 'Current students: Sign-in with your Passport York.'
    grad_intro = 'Students who have graduated: Sign-in with your Google account or a secondary, non-YorkU email ' \
                 'that is part of your student record. If your secondary non-YorkU email is not part of your student record, ' \
                 'contact the Faculty of Graduate Studies to connect it.'
    assert_includes text, ppy_intro
    assert_includes text, grad_intro

    labels = main.all('a.btn, button.btn').map(&:text)
    assert_equal ['Sign in with Passport York', 'Continue with Google', 'Email me a sign-in code'], labels

    order = [ppy_intro, 'Sign in with Passport York', grad_intro, 'Continue with Google', 'Email me a sign-in code']
    positions = order.map { |part| text.index(part) }
    assert_equal positions.sort, positions, "page order was #{positions.inspect}"

    dir = Rails.root.join('tmp/login-layout')
    FileUtils.mkdir_p(dir)
    page.save_screenshot(dir.join('graduate-login-desktop.png').to_s)
    current_window.resize_to(390, 844)
    assert page.evaluate_script('document.documentElement.scrollWidth <= window.innerWidth'), 'page overflows on a phone'
    page.save_screenshot(dir.join('graduate-login-phone.png').to_s)
  end

  test 'staff connections page labels the two record addresses as YorkU and non-YorkU email' do
    @student.update_columns(email: 'student@yorku.ca', email_external: 'student.personal@example.com')
    browser_ppy_login(@actor)
    visit staff_student_graduate_connections_path(@student)
    assert_text 'sent to the YorkU email or alternate (non-YorkU) email below'
    assert_selector '[data-record-addresses] li', text: 'YorkU email: student@yorku.ca'
    assert_selector '[data-record-addresses] li', text: 'Alternate (non-YorkU) email: student.personal@example.com'
    assert_no_text 'Contact email:'
    assert_no_text 'External contact email:'
    current_window.resize_to(1440, 1500)
    dir = Rails.root.join('tmp/login-layout')
    FileUtils.mkdir_p(dir)
    page.save_screenshot(dir.join('staff-connections-labels.png').to_s)
  end
end
