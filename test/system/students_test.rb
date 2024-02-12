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
    click_link('Continue')
    click_link('Continue')
    click_link('Continue')
    click_link('Continue')
    assert_selector '.alert-warning', text: 'Error: You have to upload a primary file to continue'
    # page.accept_alert
  end
end
