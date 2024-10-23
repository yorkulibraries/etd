# frozen_string_literal: true

require 'application_system_test_case'
require 'helpers/system_test_helper'

class StudentsTest < ApplicationSystemTestCase
  include SystemTestHelper  # Include the SystemTestHelper module here


  setup do
    @gem_record = FactoryGirl.create(:gem_record)
  end

  test 'Send student invitation email' do
    AppSettings.email_welcome_allow = true

    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)
    visit root_url
    click_link('GEM Records')
    click_link(@gem_record.studentname)
    click_link('Create ETD Student Record')
    page.accept_alert

    save_screenshot
    
    assert_selector '#send_invitation_email', text: 'Send invitation email'

    assert has_link?('Send invitation email')
    
    click_link('Send invitation email')

    assert_selector '.alert-success', text: "Sent an invitation email to #{@gem_record.studentname}"
  end

  test 'Creating a student based on GEM Records' do
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

    assert_selector "td", text: "Committee Members"
    if @gem_record.committee_members.count > 1
      @gem_record.committee_members.each do |committee_member|
        assert_selector "p", text: committee_member.full_name
      end
    end
  end

  test 'Create a new thesis and add/remove a committee member' do
    visit root_url
    click_link('GEM Records')
    click_link(@gem_record.studentname)
    click_link('Create ETD Student Record')
    page.accept_alert
    click_link('Start this thesis')
    select "EMBA", from: "thesis_degree_name"
    select "Master's", from: "thesis_degree_level"
    #click_link('Add Committee Member')
    #click_link('Remove')
    click_button('Create Thesis')
    assert_selector '.alert-success', text: 'Thesis successfully created.'
    # page.accept_alert
  end

  test 'Log in as Student and add a thesis' do
    @thesis = FactoryGirl.create(:thesis)
    login_as(@thesis.student)
    visit root_url
    fill_in('Non-YorkU Email Address', with: Faker::Internet.email)
    click_button('Continue')
    find('#select_subjects_11_chosen a.chosen-default').click
    first('#select_subjects_11_chosen .active-result').click
    click_link('Continue') #update
    click_link('Continue') #upload
    click_link('Continue') #review
    assert_selector '.alert-warning', text: 'Error: Please upload a Primary Thesis File.'
    # page.accept_alert
  end

  test 'Unblock a student' do
    visit root_url
    click_link('GEM Records')
    click_link(@gem_record.studentname)
    click_link('Create ETD Student Record')
    page.accept_alert
    click_link('Unblock student')
    page.accept_alert
    assert_no_selector '.fa fa-ban text-danger'
  end

  test 'Block a student' do
    visit root_url
    click_link('GEM Records')
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
    click_link('GEM Records')
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


  test 'Creating a thesis, pressing back and attempting to save again' do
    visit root_url
    click_link('GEM Records')
    click_link(@gem_record.studentname)
    click_link('Create ETD Student Record')
    page.accept_alert
    click_link('Start this thesis')
    select "EMBA", from: "thesis_degree_name"
    select "Master's", from: "thesis_degree_level"
    click_button('Create Thesis')
    page.go_back
    click_button('Create Thesis')
    visit root_url

    thesis_elements = all('a')

    thesis_titles = thesis_elements.map(&:text)

    # Use a set to track seen titles and duplicates
    seen_titles = Set.new
    duplicates = []

    thesis_titles.each do |title|
      if seen_titles.include?(title)
        duplicates << title
      else
        seen_titles.add(title)
      end
    end

    assert_empty duplicates, "Duplicate thesis titles found: #{duplicates.join(', ')}"
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
  should "upload primary file" do
    @thesis = FactoryGirl.create(:thesis)
    login_as(@thesis.student)
    visit root_url

    ## Page 1
    click_link("My ETD Submission")
    assert_selector "input#student_email_external"
    fill_in("Non-YorkU Email Address", with: "#{@thesis.student.username}@mailinator.com")
    click_on("Continue")

    ## Page 2: Thesis Details

    select "English", from: "thesis_language"
    fill_in "thesis_abstract", with: Faker::Lorem.paragraph

    find('#select_subjects_11_chosen a.chosen-default').click
    find('#select_subjects_11_chosen .active-result:nth-child(1)').click
    find('#select_subjects_12_chosen a.chosen-default').click
    find('#select_subjects_12_chosen .active-result:nth-child(2)').click
    find('#select_subjects_13_chosen a.chosen-default').click
    find('#select_subjects_13_chosen .active-result:nth-child(3)').click

    save_screenshot

    fill_in "thesis_keywords", with: "accounting-kw, management-kw"
    click_on("Continue")

    ## Page 3: Files and Documents

    click_on("Upload Primary Thesis File")

    # assert_no_selector("p", text: "Smith_Jane_E_2014_PhD.pdf", visible: :all)
    assert_not(page.has_css?("p", text: "Smith_Jane_E_2014_PhD.pdf"), "Should not show 'example text' as per Spring 2024 requirements")

    attach_file("document_file", Rails.root.join('test/fixtures/files/Tony_Rich_E_2012_Phd.pdf'))
    click_button('Upload')

    assert_selector(".name", text: /\.pdf/)

    click_on("Continue")

    ## Page 4: Licence Review

    assert_text("Library and Archives Canada Licence")

    # LAC Supplementary Licence File
    assert page.has_selector?('#thesis_lac_licence_agreement', visible: true), "#thesis_lac_licence_agreement not found."
    checkbox = find('#thesis_lac_licence_agreement')
    assert_not checkbox.disabled?
    checkbox.check

    check('I agree to and I have signed LAC Form', allow_label_click: true)

    assert checkbox.checked?, "#thesis_lac_licence_agreement checkbox is not checked."


    # Yorkspace Licence
    assert page.has_selector?('#thesis_yorkspace_licence_agreement', visible: true), "#thesis_yorkspace_licence_agreement not found."
    checkbox = find('#thesis_yorkspace_licence_agreement', visible: true)
    assert_not checkbox.disabled?
    click_link('View YorkSpace Licence Agreement')
    assert page.has_selector?('#yorkspace-licence', visible: true), "#yorkspace-licence not found."
    assert page.has_selector?('#thesis_yorkspace_licence_agreement', visible: true), "#thesis_yorkspace_licence_agreement not found."
    checkbox = find('#thesis_yorkspace_licence_agreement', visible: true)
    checkbox.check

    check('I agree to YorkSpace Distribution Licence', allow_label_click: true)

    assert checkbox.checked?, "#thesis_yorkspace_licence_agreement checkbox is not checked."

    # ETD Licence
    assert page.has_selector?('#thesis_etd_licence_agreement', visible: true), "#thesis_etd_licence_agreement not found."
    checkbox = find('#thesis_etd_licence_agreement', visible: true)
    assert_not checkbox.disabled?
    click_link('View ETD Licence Agreement')
    assert page.has_selector?('#etd-licence', visible: true), "#etd-licence not found."
    assert page.has_selector?('#thesis_etd_licence_agreement', visible: true), "#thesis_etd_licence_agreement not found."
    checkbox = find('#thesis_etd_licence_agreement', visible: true)
    checkbox.check

    check('I agree to ETD Licence', allow_label_click: true)

    save_screenshot

    assert checkbox.checked?, "#thesis_etd_licence_agreement checkbox is not checked."

    # Ensure you can't go next without uploading LAC Document
    click_button("Accept and Continue")
    assert_selector(".alert-warning", text: "Please upload signed LAC licence documents.")

    click_link_or_button('Upload Licence Files')
    attach_file("document_file", Rails.root.join('test/fixtures/files/Tony_Rich_E_2012_Phd.pdf'))
    click_button('Upload')

    click_button("Accept and Continue")

    ## Page 5: Submission Review
    assert_no_link('Replace')
    assert_no_link('Delete')

  end

  ## Supplementary Info displays on edit/error
  should "Supplementary Info displays on edit/error" do
    @thesis = FactoryGirl.create(:thesis)

    login_as(@thesis.student)
    visit root_url

    ## Page 1
    click_link("My ETD Submission")
    assert_selector "input#student_email_external"
    fill_in("Non-YorkU Email Address", with: "#{@thesis.student.username}@mailinator.com")
    click_on("Continue")

    ## Page 2: Thesis Details
    select "English", from: "thesis_language"
    fill_in "thesis_abstract", with: Faker::Lorem.paragraph

    find('#select_subjects_11_chosen a.chosen-default').click
    first('#select_subjects_11_chosen .active-result').click
    
    click_on("Continue")

    ## Page 3: Upload Supplementary
    click_on("Upload Supplementary Thesis Files")

    # assert_no_selector("p", text: "Smith_Jane_E_2014_PhD.pdf", visible: :all)
    # assert_not(page.has_css?("p", text: "Smith_Jane_E_2014_PhD.pdf"), "Should not show 'example text' as per Spring 2024 requirements")

    ## Upload a file not accepted format. e.g. ruby .rb
    attach_file("document_file", Rails.root.join('test/factories/thesis.rb'))
    click_button('Upload')

    assert page.has_selector?('#supplementary-help-info', visible: true), "#supplementary-help-info not found."
  end


end
