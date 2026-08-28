# frozen_string_literal: true

require 'application_system_test_case'

class AbstractPreviewTest < ApplicationSystemTestCase
  setup do
    @thesis = create(:thesis, degree_name: 'PhD', degree_level: 'Doctoral', language: 'English',
                             abstract: "First paragraph.\nStill the first paragraph.\n\nSecond paragraph.")
  end

  test 'preview distinguishes line wraps from paragraphs and follows manual corrections' do
    visit root_url
    visit edit_student_thesis_path(@thesis.student, @thesis)

    assert_selector '#abstract-paragraph-preview p', count: 2, wait: 5
    assert_selector '#abstract-paragraph-preview p', exact_text: 'First paragraph. Still the first paragraph.'
    assert_field 'Abstract', with: @thesis.abstract

    corrected = "First paragraph.\n\nNow a separate paragraph.\n \t\n\nLast paragraph."
    fill_in 'Abstract', with: corrected

    assert_selector '#abstract-paragraph-preview p', count: 3
    assert_selector '#abstract-paragraph-preview p', exact_text: 'Now a separate paragraph.'
    assert_field 'Abstract', with: corrected

    page.execute_script('arguments[0].scrollIntoView({block: "center", behavior: "instant"})', find('#abstract-preview'))
    save_screenshot('abstract-preview-desktop.png')
    current_window.resize_to(390, 844)
    page.execute_script('arguments[0].scrollIntoView({block: "center", behavior: "instant"})', find('#abstract-preview'))
    assert_selector '#abstract-paragraph-preview p', count: 3
    assert page.evaluate_script('(function () { var rect = document.getElementById("abstract-preview").getBoundingClientRect(); return rect.left >= 0 && rect.right <= document.documentElement.clientWidth; })()')
    save_screenshot('abstract-preview-mobile.png')
    current_window.resize_to(1920, 1080)

    click_button 'Update Thesis'
    assert_current_path student_thesis_path(@thesis.student, @thesis)
    # HTML form submission normalizes textarea newlines to CRLF.
    assert_equal corrected.gsub("\n", "\r\n"), @thesis.reload.abstract
  end

  test 'preview treats markup as text and handles an empty abstract' do
    visit root_url
    visit edit_student_thesis_path(@thesis.student, @thesis)
    assert_selector '#abstract-paragraph-preview', wait: 5

    text = '<img src=x onerror="alert(1)"> & <script>alert(1)</script>'
    fill_in 'Abstract', with: text

    assert_selector '#abstract-paragraph-preview p', exact_text: text
    assert_no_selector '#abstract-paragraph-preview img, #abstract-paragraph-preview script', visible: :all
    assert_field 'Abstract', with: text

    fill_in 'Abstract', with: " \n \n "
    assert_no_selector '#abstract-paragraph-preview p'
    assert_selector '#abstract-preview-empty', visible: true
  end

  test 'students can preview their abstract on the details step' do
    visit root_url
    visit student_path(@thesis.student)
    click_link 'Login as this student'
    visit student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPDATE)

    assert_selector '#abstract-paragraph-preview p', count: 2, wait: 5
    fill_in 'Abstract', with: "An indented paragraph.\n\tThis may be another paragraph."
    assert_selector '#abstract-paragraph-preview p', count: 1
    assert_selector '#abstract-paragraph-preview p', exact_text: 'An indented paragraph. This may be another paragraph.'

    fill_in 'Abstract', with: "An indented paragraph.\n\nThis is another paragraph."
    assert_selector '#abstract-paragraph-preview p', count: 2
  end
end
