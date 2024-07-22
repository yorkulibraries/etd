# frozen_string_literal: true

require 'application_system_test_case'
require 'helpers/system_test_helper'

class StudentsTest < ApplicationSystemTestCase
  include SystemTestHelper  # Include the SystemTestHelper module here

  setup do
    @gem_record = FactoryGirl.create(:gem_record)
  end

  test 'Committee Members shown in Gem Record' do
    visit root_url
    click_link('Gem Records')
    click_link(@gem_record.studentname)
    assert_selector "h6", text: "Committee Members"
    @gem_record.committee_members.each do |member|
      assert_selector "div#committee_member_#{member.id} div.col", text: "#{member.last_name}, #{member.first_name} - #{member.role}"
    end
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
