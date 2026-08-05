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

  test 'Add a permanent administrative embargo' do
    @thesis_01.update!(embargo_selection: :requested)
    request = FactoryGirl.create(:submitted_embargo_request, thesis: @thesis_01)

    visit root_url
    click_link(@thesis_01.title)
    assert_selector 'h4', text: 'Permanent administrative embargo'
    click_on('Place under permanent administrative embargo?')
    click_on('Close')
    click_on('Place under permanent administrative embargo?')
    within('#embargo_modal_textfield') do
      fill_in('Embargo Explanation', with: 'Private corporate copyright on thesis')
    end
    click_on('Place administrative embargo')
    page.accept_alert
    assert_selector 'p', text: 'This thesis has been placed under permanent embargo. It will not be published.'
    assert_selector '#embargo-requests h4', text: 'Embargo request history'
    assert_equal 'submitted', request.reload.status
  end

  test 'staff opens and approves a pending embargo request' do
    @thesis_01.update!(embargo_selection: :requested)
    create_primary_document(@thesis_01)
    request = FactoryGirl.create(:submitted_embargo_request, thesis: @thesis_01)
    letter = request.documents.embargo_letter.first
    letter.update_column(:name, 'supervisor-letter.pdf')
    supporting_document = FactoryGirl.create(
      :embargo_request_document,
      embargo_request: request,
      usage: :embargo,
      name: 'supporting-evidence.pdf'
    )
    [letter, supporting_document].each do |document|
      FileUtils.mkdir_p(File.dirname(document.file.path))
      FileUtils.cp(Rails.root.join('test/fixtures/files/pdf-document.pdf'), document.file.path)
      FileUtils.rm_f(Rails.root.join('tmp', document.name))
    end
    approved_until = EmbargoRequest.toronto_today + 1.year

    visit root_url
    assert_selector 'a.nav-link', text: /Embargo Requests/
    assert_selector 'a.nav-link .badge', text: '1'
    click_link('Embargo Requests')

    assert_selector '#embargo-requests-queue h2', text: 'Embargo Requests'
    click_link(@thesis_01.title)

    within("#embargo-request-#{request.id}") do
      assert_selector '.badge', text: 'Submitted'
      assert_link 'Download supervisor support letter'
      assert_link 'Download supporting document'
      assert_text 'supervisor-letter.pdf'
      assert_text 'supporting-evidence.pdf'
      letter_download_href = find_link('Download supervisor support letter')['href']
      supporting_download_href = find_link('Download supporting document')['href']
      assert_match(%r{/files/#{letter.id}/download\z}, letter_download_href)
      assert_match(%r{/files/#{supporting_document.id}/download\z}, supporting_download_href)

      click_link('Download supervisor support letter')
      wait_for_download('tmp/supervisor-letter.pdf')
      assert File.exist?('tmp/supervisor-letter.pdf')

      click_link('Download supporting document')
      wait_for_download('tmp/supporting-evidence.pdf')
      assert File.exist?('tmp/supporting-evidence.pdf')

      fill_in('Approve until', with: approved_until.strftime('%m/%d/%Y'))
      accept_confirm do
        click_button('Approve request')
      end
    end

    assert_selector "#embargo-request-#{request.id} .badge", text: 'Approved'
    assert_selector "#embargo-request-#{request.id} dt", text: 'Approved until'
    assert_text approved_until.strftime('%B %d, %Y')

    visit root_url
    click_link('Embargo Requests')
    assert_no_selector '#embargo-requests-queue', text: @thesis_01.title
    click_link('Approved')
    assert_selector '#embargo-requests-queue', text: @thesis_01.title

    visit logout_path
    login_as(@thesis_01.student)
    visit root_url
    visit student_view_thesis_process_path(@thesis_01, Thesis::PROCESS_STATUS)
    assert_selector '.text-bg-success', text: 'Approved'
    assert_text "Approved until #{approved_until.strftime('%B %d, %Y')}"
  end

  test 'staff declines a pending embargo request with an explanation visible to the student' do
    thesis = FactoryGirl.create(:thesis, embargo_selection: :requested)
    create_primary_document(thesis)
    request = FactoryGirl.create(:submitted_embargo_request, thesis: thesis)
    decision_notes = 'The stated basis does not meet the embargo criteria.'

    visit root_url
    click_link('Embargo Requests')
    click_link(thesis.title)

    within("#embargo-request-#{request.id}") do
      assert_selector 'textarea[required][name="embargo_request[decision_notes]"]'
      assert_selector 'textarea[name="embargo_request[decision_notes]"]:invalid'
      accept_confirm do
        click_button('Decline request')
      end
      assert_selector '.badge', text: 'Submitted'
      assert_equal 'submitted', request.reload.status

      fill_in('Decline notes', with: decision_notes)
      accept_confirm do
        click_button('Decline request')
      end
    end

    assert_selector "#embargo-request-#{request.id} .badge", text: 'Declined'
    assert_selector "#embargo-request-#{request.id}", text: decision_notes

    visit logout_path
    login_as(thesis.student)
    visit root_url
    visit student_view_thesis_process_path(thesis, Thesis::PROCESS_STATUS)
    assert_selector '.text-bg-danger', text: 'Declined'
    assert_text decision_notes
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

  private

  def create_primary_document(thesis)
    FactoryGirl.create(
      :document,
      thesis: thesis,
      user: thesis.student,
      usage: :thesis,
      supplemental: false,
      file: Rack::Test::UploadedFile.new('test/fixtures/files/Tony_Rich_E_2012_Phd.pdf')
    )
  end

  ###########################################################
  ################## END OF FILE UPLOADS ####################
  ###########################################################

end
