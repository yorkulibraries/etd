require "application_system_test_case"

class StudentsTest < ApplicationSystemTestCase
  test "visiting the index" do
    visit root_url
    page.save_screenshot('/usr/src/app/example.png')
    assert_selector "h1", text: "Student"
  end
end
