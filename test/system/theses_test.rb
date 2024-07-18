# frozen_string_literal: true

require 'application_system_test_case'
require 'helpers/system_test_helper'

class ThesesTest < ApplicationSystemTestCase
  setup do
    FactoryGirl.create(:user, role: User::ADMIN)
    FactoryGirl.create(:user, role: User::MANAGER)
    @thesis_01 = FactoryGirl.create(:thesis)
    @thesis_02 = FactoryGirl.create(:thesis, status: Thesis::UNDER_REVIEW)
  end

  test 'Assign a thesis to ME and unassign this' do
    visit root_url
    click_on('Unassigned')
    click_on('Me (')
    click_on("I'm working on it")
    # click_on('Unassign This Thesis')
    # refute_selector 'a', text: 'Unassign This Thesis'
  end

  test 'Check thesis Under review and Overview on nav-tabs' do
    visit root_url
    assert_selector 'h3', text: (/#{Regexp.escape("#{@thesis_01.title}")}/i)
    click_link(@thesis_01.title)
    click_link('Overview')
    click_link('Under Review')
    assert_selector 'h3', text: (/#{Regexp.escape("#{@thesis_02.title}")}/i)
    click_link(@thesis_02.title)
  end

  test 'Add committee member' do
    visit root_url
    click_link(@thesis_01.title)
    click_on('Make Changes')
    click_on('Add committee member')
    click_on('Close')
    click_on('Add committee member')

    fill_in('First Name', with: 'test1')
    fill_in('Last Name', with: 'test2')
    choose('Committee Member')
    click_on('Add Member')
    assert_selector 'span', text: 'test2, test1'
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
    
    click_on("Upload Primary File")
    assert_selector "p", text: "Your primary file should be in PDF format.", visible: :all
    attach_file("document_file", Rails.root.join('test/fixtures/files/Tony_Rich_E_2012_Phd.pdf'))
    click_button('Upload')

    assert_selector(".name", text: /Primary\.pdf/)
  end

  should "be able to upload supplementary document by admin/staff" do
    visit root_url
    click_link(@thesis_01.title)
    
    click_on("Upload Supplementary Files")
    assert_selector "h1", text: "Upload Supplementary File", visible: :all
    attach_file("document_file", Rails.root.join('test/fixtures/files/pdf-document.pdf'))
    assert_selector "select#document_usage"
    select "Supplementary file or document attached to thesis/dissertation", from: 'Document type' #document_usage
    click_button('Upload')
    assert_selector(".supplemental", text: /Supplemental/) #Supplemental
    
  end

  ###########################################################
  ##### TESTS WILL NEED BE UPDATED WITH NEW FILE NAMES ######
  ###########################################################

  should "be able to upload supplementary license document by admin/staff" do
    visit root_url
    click_link(@thesis_01.title)
    
    click_on("Upload Licence Files")
    assert_selector "h1", text: "Upload Supplementary Licence File", visible: :all
    attach_file("document_file", Rails.root.join('test/fixtures/files/image-example.jpg'))
    # page.driver.browser.manage.window.resize_to(1920, 2500)
    # save_screenshot()
    click_button('Upload')
    assert_not_empty find('.licence-file').text, "The .licence-file element is empty, no file"

  end

  should "be able to upload supplementary embargo document [Request for embargo document] by admin/staff" do
    visit root_url
    click_link(@thesis_01.title)
    
    page.driver.browser.manage.window.resize_to(1920, 2500)
    click_on("Upload Embargo Files")
    assert_selector "h1", text: "Upload Supplementary File", visible: :all
    attach_file("document_file", Rails.root.join('test/fixtures/files/papyrus-feature.png'))

    assert_selector "select#document_usage"
    select "Request for embargo document", from: 'Document type' #document_usage
    
    click_button('Upload')
    
    ## NOTE TO SELF, CHECK HERE FOR EMBARGO SPECIFIC
    # assert_selector(".supplemental", text: /Supplemental/) #Supplemental
    assert_not_empty find('.embargo-file').text, "The .embargo-file element is empty, no file"
    
    # Take a screenshot
    save_screenshot('screenshot_with_dropdown.png')
  end
  
  ###########################################################
  ################## END OF FILE UPLOADS ####################
  ###########################################################
  
end
