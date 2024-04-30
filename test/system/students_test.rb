# frozen_string_literal: true

require 'application_system_test_case'

class StudentsTest < ApplicationSystemTestCase
  setup do
    @gem_record = FactoryGirl.create(:gem_record)
  end

  test 'Creating a student based on Gem Records' do
    visit root_url
    click_link('Gem Records')
    click_link(@gem_record.studentname)
    click_link('Create ETD Student Record')
    page.accept_alert
    click_link('Start this thesis')
  end

  test 'Log in as Student and add a thesis' do
    @thesis = FactoryGirl.create(:thesis)
    login_as(@thesis.student)
    visit root_url
    fill_in('Non-YorkU Email Address', with: Faker::Internet.email)
    click_button('Continue')
    click_link('Continue')
    click_link('Continue')
    click_link('Continue')
    assert_selector '.alert-warning', text: 'Error: You have to upload a primary file to continue'
    # page.accept_alert
  end

  should "display student email on thesis begin_step" do
    @thesis = FactoryGirl.create(:thesis)
    login_as(@thesis.student)
    visit root_url
    click_link("My ETD Submission")
    assert_selector "h3", text: "Hello #{@thesis.student.first_name}"
    assert_selector "h6", text: "Email", visible: :all
    assert_selector "p", text: "#{@thesis.student.email}", visible: :all
  end

  should "display full name instead of first, middle and last name" do
    @thesis = FactoryGirl.create(:thesis)
    login_as(@thesis.student)
    visit root_url
    click_link("My ETD Submission")
    assert_selector "h3", text: "Hello #{@thesis.student.first_name}"
    assert_no_selector "input#student_first_name"
    assert_no_selector "input#student_middle_name"
    assert_no_selector "input#student_last_name"
    assert_selector "h6", text: "Full Name", visible: :all
    assert_selector "p", text: "#{@thesis.student.name}", visible: :all
  end


  should "not allow student to add committee members" do
    @thesis = FactoryGirl.create(:thesis)
    login_as(@thesis.student)
    visit root_url
    click_link("My ETD Submission")
    assert_selector "input#student_email_external"
    fill_in("Non-YorkU Email Address", with: "#{@thesis.student.username}@mailinator.com")
    click_on("Continue")

    # Ensure Add Committee Members button is not present.
    assert_no_selector '.student-view .card .card-body a.btn.btn-success', text: 'Add committee member'
    
    # Ensure that the close links are not present within the #committee_members section
    refute_selector("#committee_members .btn-close")
    
    # page.driver.browser.manage.window.resize_to(1920, 2500)
    save_screenshot()
  end
end

########################################
## For Debugging and building tests ##
# page.driver.browser.manage.window.resize_to(1920, 2500)
# save_screenshot()
########################################