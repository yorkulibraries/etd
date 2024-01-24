require 'application_system_test_case'

class ThesisTest < ApplicationSystemTestCase
  setup do
    FactoryGirl.create(:user, role: User::ADMIN)
    FactoryGirl.create(:user, role: User::MANAGER)
    @thesis_01 = FactoryGirl.create(:thesis)
    @thesis_02 = FactoryGirl.create(:thesis, status: Thesis::UNDER_REVIEW)
  end

  test 'Assign a thesis to ME and unassign this' do
    visit root_url
    click_on('Unassigned')
    click_on('Me')
    click_on("I'm working on it")
    # click_on('Unassign This Thesis')
    # refute_selector 'a', text: 'Unassign This Thesis'
  end

  test 'Check thesis Under review and Overview on nav-tabs' do
    visit root_url
    assert_selector 'h5', text: @thesis_01.title
    click_link(@thesis_01.title)
    click_link('Overview')
    click_link('Under Review')
    assert_selector 'h5', text: @thesis_02.title
    click_link(@thesis_02.title)
  end

  test 'Add committee member' do
    visit root_url
    click_link(@thesis_01.title)
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
end
