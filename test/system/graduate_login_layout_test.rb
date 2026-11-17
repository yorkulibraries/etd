# frozen_string_literal: true
require_relative '../support/graduate_email_browser_case'

# The public sign-in page lists Passport York first (current students), then the
# graduate options: Google, then an email code. Screenshot: tmp/login-layout/.
class GraduateLoginLayoutTest < GraduateEmailBrowserCase
  test 'passport york comes first, then the graduate options' do
    visit graduate_login_path
    main = find('main')
    text = main.text
    ppy_intro = 'If you are a current student, sign in with Passport York.'
    grad_intro = 'If you are a graduate, sign in with one of the two following options. ' \
                 'If your email address is not on your student record, contact the Faculty of Graduate Studies to connect it.'
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
    assert_text 'sent to the YorkU email or non-YorkU email below'
    assert_text 'YorkU email: student@yorku.ca'
    assert_text 'Non-YorkU email: student.personal@example.com'
    assert_no_text 'Contact email:'
    assert_no_text 'External contact email:'
    current_window.resize_to(1440, 1500)
    dir = Rails.root.join('tmp/login-layout')
    FileUtils.mkdir_p(dir)
    page.save_screenshot(dir.join('staff-connections-labels.png').to_s)
  end
end
