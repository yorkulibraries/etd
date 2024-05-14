# frozen_string_literal: true

require 'application_system_test_case'
# require '/app/test/helpers/system_test_helper'
require_relative '../helpers/system_test_helper'

class StudentsTest < ApplicationSystemTestCase
  include SystemTestHelper  # Include the SystemTestHelper module here

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

  ## Page 1 tests
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
  
  end

  ## Page 2 and 3 tests
  should "upload primary file" do 
    @thesis = FactoryGirl.create(:thesis)
    create(:loc_subject, name: "Accounting", category: "BUSINESS")
    create(:loc_subject, name: "Management", category: "BUSINESS")
    create(:loc_subject, name: "Finance", category: "BUSINESS")

    login_as(@thesis.student)
    visit root_url

    ## Page 1
    click_link("My ETD Submission")
    assert_selector "input#student_email_external"
    fill_in("Non-YorkU Email Address", with: "#{@thesis.student.username}@mailinator.com")
    click_on("Continue")

    ## Page 2
    select "English", from: "thesis_language"
    fill_in "thesis_abstract", with: Faker::Lorem.paragraph

    select_option_value = 'Accounting'
    select_chosen_option('#select_subjects_11_chosen', select_option_value)

    select_option_value = 'Management'
    select_chosen_option('#select_subjects_12_chosen', select_option_value)

    select_option_value = 'Finance'
    select_chosen_option('#select_subjects_13_chosen', select_option_value)

    fill_in "thesis_keywords", with: "accounting-kw, management-kw"
    click_on("Continue")

    ## Page 3 

    click_on("Upload Primary File")
    assert_selector "p", text: "Your primary file should be in PDF format.", visible: :all
    
    # assert_no_selector("p", text: "Smith_Jane_E_2014_PhD.pdf", visible: :all)
    assert_not(page.has_css?("p", text: "Smith_Jane_E_2014_PhD.pdf"), "Should not show 'example text' as per Spring 2024 requirements")
    
    attach_file("document_file", Rails.root.join('test/fixtures/files/Tony_Rich_E_2012_Phd.pdf'))
    click_button('Upload')

    assert_selector('p', text: /Primary\.pdf/)

    # page.driver.browser.manage.window.resize_to(1920, 2500)
    save_screenshot()

    # File.open("tmp/test-screenshots/error.html", "w") { |file| file.write(page.html) }    
    save_page()

    # create(:document, thesis:, supplemental: false, file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))
  end


end

########################################
## For Debugging and building tests ##
# page.driver.browser.manage.window.resize_to(1920, 2500)
# save_screenshot()
########################################