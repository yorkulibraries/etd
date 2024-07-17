# frozen_string_literal: true

require 'application_system_test_case'

class ThesesTest < ApplicationSystemTestCase
  setup do
    FactoryGirl.create(:user, role: User::ADMIN)
    FactoryGirl.create(:user, role: User::MANAGER)
    @thesis_01 = FactoryGirl.create(:thesis, degree_name: 'IMBA', degree_level: 'Master\'s')
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
    assert_selector 'h3', text: @thesis_01.title
    click_link(@thesis_01.title)
    click_link('Overview')
    click_link('Under Review')
    assert_selector 'h3', text: @thesis_02.title
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

  test 'Remove committee member' do
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

    accept_confirm do
      find('span.fw-bold', text: 'test2, test1').find(:xpath, '../../div[@class="col-1"]/a[@class="btn btn-close pull-right"]').click
    end

    page.accept_alert
    assert_no_selector 'span', text: 'test2, test1'
  end

  test 'Edit a thesis' do
    visit root_url
    click_link(@thesis_01.title)
    click_on('Make Changes')

    fill_in "thesis_title", with: "title 10 (test)"
    fill_in "thesis_program", with: "program 10 (test)"
    fill_in "thesis_abstract", with: "Testing Abstract"
    click_button('Update Thesis')

    assert_selector 'h3', text: 'title 10 (test)', visible: true

    assert_selector 'p', text: 'program 10 (test)', visible: true

    assert_selector 'p', text: 'Testing Abstract', visible: true
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
end
