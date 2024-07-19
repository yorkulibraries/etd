# frozen_string_literal: true

require 'application_system_test_case'
require 'helpers/system_test_helper'

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

  test 'Gem Record has committee members' do
    visit root_url
    click_link('Gem Records')
    click_link(@gem_record.studentname)

    assert_selector "h6", text: "Committee Members"
    if @gem_record.committee_members.count > 1
      @gem_record.committee_members.each do |committee_member|
        assert_selector "p", text: committee_member.full_name
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

    # Set the AppSettings values
    AppSettings.student_review_license_yorkspace = "<div>A Software Licence Agreement, commonly known as an <strong>End User Licence
  Agreement (EULA)</strong>, is a contract that allows a user to buy the rights to
  use a computer program, software, or application. This agreement does not transfer
  ownership of the software but permits the buyer to use it according to certain terms
  and conditions.<br><br></div><div>An EULA often appears as a pop-up before or after
  you download a program or install an update on your computer. Software programs
  sold through a retailer or mail order may come with a physical copy of a licence
  agreement.&nbsp;<br><br></div><div>Whether it appears in digital or physical form,
  this agreement is important for software developers who want to maintain some control
  over the use and distribution of their intellectual property.&nbsp;</div>"

    AppSettings.student_review_license_etd = "'<div>In addition to the licence terms mentioned above, LawDepot?s EULA template
  also addresses provisions such as:<br><br></div><ul><li><strong>Limitation of liability</strong>:
  limits the consequences a vendor may face if issues stem from the use of their software</li><li><strong>Warrants
  and representations</strong>: clarifies copyright</li><li><strong>Termination</strong>:
  outlines the process of termination if the end-user fails to comply with the agreement</li><li><a
  href=\"https://www.lawdepot.com/force-majeure\"><strong>Force Majeure</strong></a>:
  limits the vendor?s liability when problems arise from an unforeseen and uncontrollable
  event (e.g., if a natural disaster causes the product to malfunction)</li></ul><div>If
  needed, you can add a clause that?s specific to your product and not already included
  in the template. For example, a vendor may need to detail further restrictions on
  the end-user because the product allows users to create content. In this case, the
  vendor may reserve the right to moderate content that meets certain criteria (e.g.,
  ?A non-exhaustive list of content that may be rejected by the Software Publisher
  includes??).<br><br></div><div>When using LawDepot?s EULA template to write your
  own clause, follow these tips:<br><br></div><ul><li>Use everyday language and full
  sentences.&nbsp;</li><li>Capitalize any defined terms, such as Licensee and Vendor.</li><li>Do
  not use pronouns (e.g. ?we? and ?they?) to refer to the parties in the agreement.</li></ul><div>Contact
  a local attorney if you?re unsure how to address a particular use for your Software
  Licence Agreement.&nbsp;<br><br></div>"

    login_as(@thesis.student)
    visit root_url

    # Set Page size
    page.driver.browser.manage.window.resize_to(1920, 2500)
    
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

    assert_selector(".name", text: /Primary\.pdf/)

    click_on("Continue")

    
    ## Page 4
    
    assert_text "LAC Supplementary Licence File Upload"
    
    # Initially, checkboxes should be disabled if not checked
    assert page.has_unchecked_field?('thesis_yorkspace_licence_agreement', disabled: true)
    assert page.has_unchecked_field?('thesis_etd_licence_agreement', disabled: true)

    # Scroll through Yorkspace Licence
    assert page.has_selector?('#yorkspace-licence', visible: true), "ERROR: Yorkspace-licence not found."

    # Wait for the Yorkspace Licence content to be rendered
    # assert_selector '#yorkspace-licence', visible: true

    # Scroll to the bottom of the scrollable content to enable the checkbox
    page.execute_script('document.getElementById("yorkspace-licence").scrollTop = document.getElementById("yorkspace-licence").scrollHeight')

    # Ensure the checkbox is enabled
    # assert find('#thesis_yorkspace_licence_agreement').enabled?
    # assert_not find('#thesis_yorkspace_licence_agreement').disabled?, "ERROR: Yorkspace licence agreement checkbox is not enabled."
    
    checkbox = find('#thesis_yorkspace_licence_agreement')
    assert_not checkbox.disabled?, "ERROR: Yorkspace licence agreement checkbox is not enabled."
 
    # Check the checkbox
    checkbox.check
 
    # Verify that the checkbox is checked
    assert checkbox.checked?, "ERROR: Yorkspace licence agreement checkbox is not checked."
   
  end
end

########################################
## For Debugging and building tests ##
# page.driver.browser.manage.window.resize_to(1920, 2500)
# save_screenshot()
## HTML Save
# File.open("tmp/test-screenshots/error.html", "w") { |file| file.write(page.html) }    
# save_page()
########################################