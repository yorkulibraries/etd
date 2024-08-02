# frozen_string_literal: true

require 'application_system_test_case'
require 'helpers/system_test_helper'

class UsersTest < ApplicationSystemTestCase
  include SystemTestHelper  # Include the SystemTestHelper module here

  setup do
    @user1 = FactoryGirl.create(:user)
    @user2 = FactoryGirl.create(:user)
    @user3 = FactoryGirl.create(:user)
  end

  test 'Create a user' do
    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)
    visit root_url
    find('i.fa.fa-cog').click
    click_link("Users")
    click_link("New User")
    fill_in('Name *', with: "Test User")
    fill_in('Email *', with: "test@me.ca")
    fill_in('Username *', with: "testadminuser")
    select "Admin", from: 'user_role'
    click_button("Create User")

    assert_selector '.alert-success', text: "Successfully created user testadminuser."
    assert_selector 'a', text: "Test User"
    assert_selector 'span', text: "test@me.ca"
  end

  test 'Update a user' do
    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)
    visit root_url
    find('i.fa.fa-cog').click
    click_link("Users")
    click_link(@user1.name)
    fill_in('Name *', with: "Test User")
    fill_in('Email *', with: "test@me.ca")
    fill_in('Username *', with: "testadminuser")
    click_button("Update User")

    assert_selector '.alert-success', text: "Successfully updated user testadminuser."
    assert_selector 'a', text: "Test User"
    assert_selector 'span', text: "test@me.ca"
  end

  test 'Block a user' do
    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)
    visit root_url
    find('i.fa.fa-cog').click
    click_link("Users")
    find(:xpath, ".//a[@href='/users/#{@user1.id}/block']").click
    page.accept_alert
    click_link("Blocked Users")

    assert_selector 'span', text:  @user1.email
  end

  test 'Unblock a user' do
    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)
    visit root_url
    find('i.fa.fa-cog').click
    click_link("Users")
    find(:xpath, ".//a[@href='/users/#{@user1.id}/block']").click
    page.accept_alert
    click_link("Blocked Users")
    assert_selector 'span', text:  @user1.email
    find(:xpath, ".//a[@href='/users/#{@user1.id}/unblock']").click
    page.accept_alert
    click_link("Active Users")
    assert_selector 'span', text:  @user1.email
  end

  test 'Viewing user activity' do
    user = FactoryGirl.create(:user, role: User::ADMIN)
    login_as(user)
    visit root_url
    find('i.fa.fa-cog').click
    click_link("Users")
    find(:xpath, ".//a[@href='/users/#{@user1.id}/activity']").click

    assert_selector 'h1', text: "#{@user1.name} - Activity"
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
