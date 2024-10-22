# frozen_string_literal: true

require 'application_system_test_case'
require 'helpers/system_test_helper'

class AppSettingsTest < ApplicationSystemTestCase
  include SystemTestHelper  # Include the SystemTestHelper module here

  setup do
    @gem_record = FactoryGirl.create(:gem_record)
  end

  test 'Student submission Begin Submission message' do
    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)

    visit root_url

    click_link("Settings")

    find('trix-editor#app_settings_student_begin_submission').click.set('Welcome Message Text Test')

    click_button('Save Settings')

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

    click_link("Students")
    click_link(@gem_record.studentname)
    click_link("Login as this student")

    within('div.student-view') do
      assert_text "Welcome Message Text Tes"
    end
  end

  test 'Student submission Update Details message' do
    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)
    visit root_url
    click_link("Settings")
    click_button('Update details')
    find('trix-editor#app_settings_student_update_details_initial').click.set('Initial Text Test')
    find('#app_settings_student_update_details_abstract').click.set('Abstract Text Test')
    find('#app_settings_student_update_details_subjects').click.set('Subjects Text Test')
    find('#app_settings_student_update_details_keywords').click.set('Keywords Text Test')
    click_button('Save Settings')
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
    click_link("Students")
    click_link(@gem_record.studentname)
    click_link("Login as this student")
    fill_in 'student_email_external', with: 'test@test.com'
    click_button('Continue')
    #assert_selector "small", text: 'Initial Text Test'
    assert_selector "small", text: 'Abstract Text Test'
    assert_selector "small", text: 'Subjects Text Test'
    assert_selector "small", text: 'Keywords Text Test'
  end

  test 'Student submission Upload files message' do
    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)
    visit root_url
    click_link("Settings")
    click_button('Upload files')
    find('trix-editor#app_settings_student_upload_files').click.set('Upload Files Text Test')
    find('trix-editor#app_settings_student_supplementary_upload_files').click.set('Supplementary Upload files Text Test')
    find('trix-editor#app_settings_student_supplementary_embargo_upload_files').click.set('Supplementary Embargo Upload files Text Test')
    click_button('Save Settings')
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
    click_link("Students")
    click_link(@gem_record.studentname)
    click_link("Login as this student")
    fill_in 'student_email_external', with: 'test@test.com'
    click_button('Continue')
    fill_in 'thesis_abstract', with: 'Abstract Text Test'
    find('#select_subjects_11_chosen a.chosen-default').click
    first('#select_subjects_11_chosen .active-result').click
    click_link('Continue')
    assert_text "Upload Files Text Test"
    click_link_or_button('Upload Supplementary Thesis Files')
    within('div.modal-body') do
      assert_text "Supplementary Upload files Text Test"
    end
  end

  test 'Student submission Review Licences message' do
    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)
    visit root_url
    click_link("Settings")
    click_button('Review Licences')
    find('trix-editor#app_settings_student_review_license_info').click.set('Review Licence Info Text Test')
    find('trix-editor#app_settings_student_review_license_lac').click.set('LAC licence Text Test')
    find('trix-editor#app_settings_student_review_license_yorkspace').click.set('YorkSpace Non-Exclusive Distribution Licence Text Test')
    find('trix-editor#app_settings_student_review_license_etd').click.set('YorkU ETD Licence Text Test')
    click_button('Save Settings')
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
    click_link("Students")
    click_link(@gem_record.studentname)
    click_link("Login as this student")
    fill_in 'student_email_external', with: 'test@test.com'
    click_button('Continue')
    fill_in 'thesis_abstract', with: 'Abstract Text Test'
    find('#select_subjects_11_chosen a.chosen-default').click
    first('#select_subjects_11_chosen .active-result').click
    click_link('Continue')
    click_link_or_button('Upload Primary Thesis File')
    attach_file('document_file', Rails.root.join('test/fixtures/files/pdf-document.pdf'))
    click_button('Upload')
    click_link('Continue')
    assert_selector 'div.student-view.fitted.submit > div', text: 'Review Licence Info Text Test'

    click_button('Accept and Continue')
  end

  test 'Student submission Submit Review message' do
    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)
    visit root_url
    click_link("Settings")
    click_button('Submit for Review')
    find('trix-editor#app_settings_student_submit_for_review').click.set('Submit for Review Text Test')
    click_button('Save Settings')
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
    click_link("Students")
    click_link(@gem_record.studentname)
    click_link("Login as this student")
    fill_in 'student_email_external', with: 'test@test.com'
    click_button('Continue')
    fill_in 'thesis_abstract', with: 'Abstract Text Test'
    find('#select_subjects_11_chosen a.chosen-default').click
    first('#select_subjects_11_chosen .active-result').click
    click_link('Continue')
    click_link_or_button('Upload Primary Thesis File')
    attach_file('document_file', Rails.root.join('test/fixtures/files/pdf-document.pdf'))
    click_button('Upload')
    click_link('Continue')
    click_link_or_button('Upload Licence Files')
    attach_file('document_file', Rails.root.join('test/fixtures/files/pdf-document.pdf'))
    click_button('Upload')
    check 'thesis_lac_licence_agreement'
    assert_selector "input[type=checkbox][id=thesis_lac_licence_agreement]:checked"
    check 'thesis_yorkspace_licence_agreement'
    assert_selector "input[type=checkbox][id=thesis_yorkspace_licence_agreement]:checked"
    check 'thesis_etd_licence_agreement'
    assert_selector "input[type=checkbox][id=thesis_etd_licence_agreement]:checked"
    click_button('Accept and Continue')
    assert_text 'Submit for Review Text Test'
  end
end

