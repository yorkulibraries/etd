# frozen_string_literal: true

require 'application_system_test_case'
require 'helpers/system_test_helper'

class StudentsTest < ApplicationSystemTestCase
  #include SystemTestHelper  # Include the SystemTestHelper module here
  #include SystemTestHelper  # Include the SystemTestHelper module here

  setup do
    @gem_record = FactoryGirl.create(:gem_record)
  end

  test 'Send student invitation email' do
    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)
    visit root_url
    click_link('Gem Records')
    click_link(@gem_record.studentname)
    click_link('Create ETD Student Record')
    page.accept_alert

    click_link('Send invitation email')

    assert_selector '.alert-success', text: "Sent an invitation email to #{@gem_record.studentname}"
  end

  test 'Creating a student based on Gem Records' do
    visit root_url
    click_link('GEM Records')
    click_link(@gem_record.studentname)
    click_link('Create ETD Student Record')
    page.accept_alert
    click_link('Start this thesis')
  end

  test 'Starting a thesis' do
    visit root_url
    click_link('GEM Records')
    click_link(@gem_record.studentname)
    click_link('Create ETD Student Record')
    page.accept_alert
    click_link('Start this thesis')
    select "EMBA", from: "thesis_degree_name"
    select "Master's", from: "thesis_degree_level"
    click_button('Create Thesis')
    assert_selector "a", text: @gem_record.studentname
  end

  test 'Editing a student' do
    visit root_url
    click_link('GEM Records')
    click_link(@gem_record.studentname)
    click_link('Create ETD Student Record')
    page.accept_alert
    click_link('Make changes')

    fill_in('Email *', with: "test@test.com")
    fill_in('Name *', with: "#{@gem_record.studentname} (test)")
    click_button('Update Student')

    assert_selector 'p', text: "test@test.com", visible: true
    assert_selector 'h1', text: "#{@gem_record.studentname} (test)", visible: true
  end

  test 'Gem Record has committee members' do
    visit root_url
    click_link('GEM Records')
    click_link(@gem_record.studentname)

    assert_selector "h6", text: "Committee Members"
    if @gem_record.committee_members.count > 1
      @gem_record.committee_members.each do |committee_member|
        assert_selector "p", text: committee_member.full_name
      end
    end
    end
  end

  test 'Log in as Student and add a thesis' do
    @thesis = FactoryGirl.create(:thesis)
    login_as(@thesis.student)
    visit root_url
    fill_in('Non-YorkU Email Address', with: Faker::Internet.email)
    click_button('Continue')
    click_link('Continue') #update
    click_link('Continue') #upload
    click_link('Continue') #review
    assert_selector '.alert-warning', text: 'Error: You have to upload a primary file to continue'
    # page.accept_alert
  end

  test 'Unblock a student' do
    visit root_url
    click_link('Gem Records')
    click_link(@gem_record.studentname)
    click_link('Create ETD Student Record')
    page.accept_alert
    click_link('Unblock student')
    page.accept_alert
    assert_no_selector '.fa fa-ban text-danger'
  end

  test 'Block a student' do
    visit root_url
    click_link('Gem Records')
    click_link(@gem_record.studentname)
    click_link('Create ETD Student Record')
    page.accept_alert
    click_link('Unblock student')
    page.accept_alert
    assert_no_selector '.fa fa-ban text-danger'
    click_link('Block student')
    page.accept_alert
    assert_selector '.fa-ban'
  end

  test 'View student audit trail' do
    visit root_url
    click_link('Gem Records')
    click_link(@gem_record.studentname)
    click_link('Create ETD Student Record')
    page.accept_alert
    click_link('Audit trail')
    assert_selector "h3", text: "Audit Trail"
  end

  ## Page 1 tests
  should "display student email on thesis begin_step" do
    @thesis = FactoryGirl.create(:thesis)
    login_as(@thesis.student)
    visit root_url
    click_link("My ETD Submission")
    assert_text(/#{Regexp.escape("Hello #{@thesis.student.first_name}")}/i)
    assert_selector "h4", text: "Email", visible: :all
    assert_selector "p", text: "#{@thesis.student.email}", visible: :all
  end

  should "display full name instead of first, middle and last name" do
    @thesis = FactoryGirl.create(:thesis)
    login_as(@thesis.student)
    visit root_url
    click_link("My ETD Submission")
    assert_text(/#{Regexp.escape("Hello #{@thesis.student.first_name}")}/i)
    assert_no_selector "input#student_first_name"
    assert_no_selector "input#student_middle_name"
    assert_no_selector "input#student_last_name"
    assert_selector "h4", text: "Full Name", visible: :all
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
  should "Successfully Submit Student Thesis" do
    @thesis = FactoryGirl.create(:thesis)
    create(:loc_subject, name: "Accounting", category: "BUSINESS")
    create(:loc_subject, name: "Management", category: "BUSINESS")
    create(:loc_subject, name: "Finance", category: "BUSINESS")

    login_as(@thesis.student)
    visit root_url

    ## Page 1: Welcome and Non-YorkU Email


    click_link("My ETD Submission")
    assert_selector "input#student_email_external"
    fill_in("Non-YorkU Email Address", with: "#{@thesis.student.username}@mailinator.com")
    click_on("Continue")

    ## Page 2: Thesis Details

    select "English", from: "thesis_language"
    fill_in "thesis_abstract", with: Faker::Lorem.paragraph


    execute_script("document.getElementById('select_subjects_11').style.display = 'block';")
    select "Accounting", from: 'select_subjects_11'

    execute_script("document.getElementById('select_subjects_12').style.display = 'block';")
    select "Management", from: 'select_subjects_12'

    execute_script("document.getElementById('select_subjects_13').style.display = 'block';")
    select "Finance", from: 'select_subjects_13'

    select "Accounting", from: 'select_subjects_11'
    select "Management", from: 'select_subjects_12'
    select "Finance", from: 'select_subjects_13'

    execute_script("document.getElementById('select_subjects_11').style.display = 'block';")
    select "Accounting", from: 'select_subjects_11'

    execute_script("document.getElementById('select_subjects_12').style.display = 'block';")
    select "Management", from: 'select_subjects_12'

    execute_script("document.getElementById('select_subjects_13').style.display = 'block';")
    select "Finance", from: 'select_subjects_13'

    select "Accounting", from: 'select_subjects_11'
    select "Management", from: 'select_subjects_12'
    select "Finance", from: 'select_subjects_13'

    fill_in "thesis_keywords", with: "accounting-kw, management-kw"
    click_on("Continue")

    ## Page 3: Files and Documents

    click_on("Upload Primary File")
    assert_selector "p", text: "Your primary file should be in PDF format.", visible: :all

    # assert_no_selector("p", text: "Smith_Jane_E_2014_PhD.pdf", visible: :all)
    assert_not(page.has_css?("p", text: "Smith_Jane_E_2014_PhD.pdf"), "Should not show 'example text' as per Spring 2024 requirements")

    attach_file("document_file", Rails.root.join('test/fixtures/files/Tony_Rich_E_2012_Phd.pdf'))
    click_button('Upload')

    assert_selector(".name", text: /\.pdf/)

    click_on("Continue")

    ## Page 4: Licence Review

>>>>>>> 6359df5 (Remove Licence Scrolling into Collapseable)
    assert_text("LAC Supplementary Licence File Upload")

    # Yorkspace Licence
    assert page.has_selector?('#thesis_yorkspace_licence_agreement', visible: true), "#thesis_yorkspace_licence_agreement not found."
    checkbox = find('#thesis_yorkspace_licence_agreement')
    assert_not checkbox.disabled?
    click_link('View YorkSpace Licence Agreement')
    assert page.has_selector?('#yorkspace-licence', visible: true), "#yorkspace-licence not found."
    checkbox.check
    assert checkbox.checked?, "#thesis_yorkspace_licence_agreement checkbox is not checked."

    # ETD Licence
    assert page.has_selector?('#thesis_etd_licence_agreement', visible: true), "#thesis_etd_licence_agreement not found."
    checkbox = find('#thesis_etd_licence_agreement')
    assert_not checkbox.disabled?
    click_link('View ETD Licence Agreement')
    assert page.has_selector?('#etd-licence', visible: true), "#etd-licence not found."
    checkbox.check
    assert checkbox.checked?, "Yorkspace licence agreement checkbox is not checked."

    click_button("Accept and Continue")

    ## Page 5: Submission Review


  end
end
