# frozen_string_literal: true

require 'application_system_test_case'
require 'helpers/system_test_helper'

class ThesesTest < ApplicationSystemTestCase
  include SystemTestHelper  # Include the SystemTestHelper module here

  setup do
    FactoryGirl.create(:user, role: User::ADMIN)
    FactoryGirl.create(:user, role: User::MANAGER)
    @thesis_01 = FactoryGirl.create(:thesis, degree_name: 'IMBA', degree_level: 'Master\'s')
    @thesis_02 = FactoryGirl.create(:thesis, status: Thesis::UNDER_REVIEW)
  end

  test "be able to download report" do
    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)
    visit root_url
    click_link("Reports")
    click_link("Under Review Theses")
    assert_selector 'a', text: 'Download Excel'
    click_link("Download Excel")
    # workaround until we figure out how to deal with download using remote browser
    if !ENV["SELENIUM_REMOTE_URL"].present?
      filename = "tmp/theses_report.xlsx"
      #wait_for_download(filename, 90)
      #assert File.exist?(filename), "Expected file #{filename} to be downloaded"
      #File.delete(filename)
    end
  end

  test 'Assign a thesis to Me' do
    visit root_url
    click_on('Unassigned')
    click_on('Me (')
    click_on("I'm working on it")
  end

  test 'Check thesis Under review and Overview on nav-tabs' do
    visit root_url
    assert_selector 'h2', text: (/#{Regexp.escape("#{@thesis_01.title}")}/i)
    click_link(@thesis_01.title)
    click_link('ETD')
    click_link('Under Review')
    assert_selector 'h2', text: (/#{Regexp.escape("#{@thesis_02.title}")}/i)
    click_link(@thesis_02.title)
  end

  test 'Add committee member' do
    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)

    visit root_url
    click_link(@thesis_01.title)
    click_on('Make Changes')
    click_on('Add committee member')

    fill_in('First Name', with: 'test1')
    fill_in('Last Name', with: 'test2')
    choose('Committee Member')
    click_on('Add')
    assert_selector 'span', text: 'test2, test1'
  end

  test 'Remove committee member' do
    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)

    visit root_url
    click_link(@thesis_01.title)
    click_on('Make Changes')
    
    click_on('Add committee member')
    fill_in('First Name', with: 'f1')
    fill_in('Last Name', with: 'l1')
    choose('Committee Member')
    click_on('Add')

    save_screenshot

    assert_selector 'span', text: 'l1, f1'

    click_on('Add committee member')
    fill_in('First Name', with: 'f2')
    fill_in('Last Name', with: 'l2')
    choose('Chair')
    click_on('Add')

    save_screenshot

    assert_selector 'span', text: 'l2, f2'

    remove1 = 'Remove l1, f1 (Committee Member)'
    remove2 = 'Remove l2, f2 (Chair)'

    page.find_link(remove1)
    page.find_link(remove2)

    assert has_link?(remove1)
    assert has_link?(remove2)
    
    click_link_or_button(remove1)
    
    assert_no_selector 'span', text: 'l1, f1'
    assert_no_link(remove1)

    assert_selector 'span', text: 'l2, f2'

    assert has_link?(remove2)
  end

  test 'Edit a thesis' do
    visit root_url
    click_link(@thesis_01.title)
    click_on('Make Changes')

    fill_in "thesis_title", with: "title 10 (test)"
    fill_in "thesis_program", with: "program 10 (test)"
    fill_in "thesis_abstract", with: "Testing Abstract"
    click_button('Update Thesis')

    assert_selector 'h2', text: 'title 10 (test)', visible: true

    assert_selector 'p', text: 'program 10 (test)', visible: true

    assert_selector 'p', text: 'Testing Abstract', visible: true
  end

  test 'Edit a thesis with errors' do
    visit root_url
    click_link(@thesis_01.title)
    click_on('Make Changes')

    fill_in "thesis_title", with: ""
    fill_in "thesis_program", with: ""
    click_button('Update Thesis')

    assert_no_selector '.alert-success', text: 'Successfully updated thesis.'
  end

  test 'Returning a thesis' do
    visit root_url
    click_link(@thesis_01.title)

    find('a.btn.btn-secondary.btn-sm.dropdown-toggle').click
    choose('status', option: 'under_review')
    click_on('Change Status')


    find('a.btn.btn-secondary.btn-sm.dropdown-toggle').click
    choose('status', option: 'returned')
    click_on('Change Status')

    assert_selector 'span.badge.bg-primary', text: 'Returned'
  end

  test 'Accepting a thesis' do
    visit root_url
    click_link(@thesis_01.title)

    find('a.btn.btn-secondary.btn-sm.dropdown-toggle').click
    choose('status', option: 'under_review')
    click_on('Change Status')


    find('a.btn.btn-secondary.btn-sm.dropdown-toggle').click
    choose('status', option: 'accepted')
    click_on('Change Status')

    assert_selector 'span.badge.bg-primary', text: 'Accepted'
  end

  test 'Add an embargo' do
    visit root_url
    click_link(@thesis_01.title)
    click_on('Place under permanent embargo?')
    click_on('Close')
    click_on('Place under permanent embargo?')
    within('#embargo_modal_textfield') do
      fill_in('Embargo Explanation', with: 'Private corporate copyright on thesis')
    end
    click_on('Place Embargo')
    page.accept_alert
    assert_selector 'p', text: 'This thesis has been placed under permanent embargo. It will not be published.'
  end

  #### FILE UPLOADS FROM BACKEND #####

  should "be able to upload primary document by admin/staff" do
    visit root_url
    click_link(@thesis_01.title)

    click_on("Upload Primary Thesis File")
    attach_file("document_file", Rails.root.join('test/fixtures/files/Tony_Rich_E_2012_Phd.pdf'))
    click_button('Upload')

    assert_selector(".name", text: /\.pdf/)
  end

  should "not upload primary document with incorrect file format" do
    visit root_url
    click_link(@thesis_01.title)

    click_on("Upload Primary Thesis File")
    attach_file("document_file", Rails.root.join('test/fixtures/files/image-example.jpg'))
    click_button('Upload')

    assert_selector(".invalid-feedback", text: "File extension .jpg is not allowed.")
  end

  should "not upload supplmentary document with incorrect file format as student" do
    visit root_url
    click_link("Students")
    click_link(@thesis_01.student.name)

    click_link("Login as this student")

    fill_in("Non-YorkU Email Address", with: "#{@thesis_01.student.username}@mailinator.com")
    click_on("Continue")

    fill_in("Abstract", with: "Abstract Test")

    find('#select_subjects_11_chosen a.chosen-default').click
    first('#select_subjects_11_chosen .active-result').click
    
    click_on("Continue")

    click_on("Upload Supplementary Thesis Files")
    attach_file("document_file", Rails.root.join('test/fixtures/files/zip-file.zip'))

    click_button('Upload')
        
    assert_selector(".invalid-feedback", text: "File extension .zip is not allowed.")
  end

  should "not upload supplmentary document with incorrect file format as admin" do
    visit root_url
    click_link(@thesis_01.title)

    click_on("Upload Supplementary Thesis Files")
    attach_file("document_file", Rails.root.join('test/fixtures/files/zip-file.zip'))
    click_button('Upload')

    assert_selector(".invalid-feedback", text: "File extension .zip is not allowed.")
  end

  should "be able to upload supplementary document by admin/staff" do
    visit root_url
    click_link(@thesis_01.title)

    click_on("Upload Supplementary Thesis Files")
    assert_selector "h2", text: "Upload Supplementary Thesis File", visible: :all
    attach_file("document_file", Rails.root.join('test/fixtures/files/pdf-document.pdf'))
    click_button('Upload')
    assert_selector(".supplemental", text: /_supplemental_/) #Supplemental

  end
  ###########################################################
  ##### TESTS WILL NEED BE UPDATED WITH NEW FILE NAMES ######
  ###########################################################

  should "be able to upload supplementary licence document by admin/staff" do
    visit root_url
    click_link(@thesis_01.title)

    click_on("Upload Licence Agreements")
    assert_selector "h2", text: "Upload Licence File", visible: :all
    attach_file("document_file", Rails.root.join('test/fixtures/files/Tony_Rich_E_2012_Phd.pdf'))
    click_button('Upload')
    assert_not_empty find('.licence-file').text, "The .licence-file element is empty, no file"

  end

  should "be able to upload supplementary embargo document [Request for embargo document] by admin/staff" do
    visit root_url
    click_link(@thesis_01.title)

    click_on("Upload Embargo Documents")
    assert_selector "h2", text: "Upload Embargo Documents", visible: :all

    attach_file("document_file", Rails.root.join('test/fixtures/files/Tony_Rich_E_2012_Phd.pdf'))
    click_button('Upload')

    assert_not_empty find('.embargo-file').text, "The .embargo-file element is empty, no file"
  end

  should "update primary thesis file" do
    visit root_url
    click_link(@thesis_01.title)

    click_on("Upload Primary Thesis File")
    attach_file("document_file", Rails.root.join('test/fixtures/files/Tony_Rich_E_2012_Phd.pdf'))
    click_button('Upload')

    click_link("Replace")
    attach_file("document_file", Rails.root.join('test/fixtures/files/Tony_Rich_E_2012_Phd.pdf'))
    click_button('Upload')
    assert_selector(".name", text: /\.pdf/)

    click_link("Delete")
    page.accept_alert

    assert_selector "p", text: "There are no primary thesis files."
  end

  should "update supplementary file" do
    visit root_url
    click_link(@thesis_01.title)

    click_on("Upload Supplementary Thesis Files")
    attach_file("document_file", Rails.root.join('test/fixtures/files/Tony_Rich_E_2012_Phd.pdf'))
    click_button('Upload')

    click_link("Replace")
    attach_file("document_file", Rails.root.join('test/fixtures/files/Tony_Rich_E_2012_Phd.pdf'))
    click_button('Upload')
    assert_selector(".name", text: /\.pdf/)

    click_link("Delete")
    page.accept_alert

    assert_selector "p", text: "There are no supplementary thesis files."
  end

  ###########################################################
  ################## END OF FILE UPLOADS ####################
  ###########################################################

end
