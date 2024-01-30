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
    page.save_screenshot('example01.png')
    click_link('Update details')
    page.save_screenshot('example02-a.png', full: true)
    page.execute_script 'window.scrollBy(0,2000)'
    sleep 1
    page.save_screenshot('example02-b.png', full: true)
    click_link('Upload files')
    page.save_screenshot('example03.png')
    click_link('Review details')
    page.save_screenshot('example04.png')
  end
end
