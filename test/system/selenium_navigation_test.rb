# frozen_string_literal: true

require 'application_system_test_case'

class SeleniumNavigationTest < ApplicationSystemTestCase
  def setup
    super
    assert_selector 'h1', text: 'Overview'
    @native_displayed = page.driver.options[:native_displayed]
    page.driver.options[:native_displayed] = false
  end

  def teardown
    page.driver.options[:native_displayed] = @native_displayed
    super
  end

  test 'visibility reloads an element detached during navigation' do
    error = Selenium::WebDriver::Error::UnknownError.new('Node with given id does not belong to the document')
    Selenium::WebDriver::Element.any_instance.stubs(:displayed?).raises(error).then.returns(true)

    assert_selector 'h1', text: 'Overview'
  end

  test 'unrelated browser errors are not retried or hidden' do
    error = Selenium::WebDriver::Error::UnknownError.new('Unexpected browser failure')
    Selenium::WebDriver::Element.any_instance.stubs(:displayed?).raises(error)

    raised = assert_raises(Selenium::WebDriver::Error::UnknownError) do
      assert_selector 'h1', text: 'Overview'
    end
    assert_includes raised.message, 'Unexpected browser failure'
  end

  test 'persistently detached elements still fail at the normal wait limit' do
    error = Selenium::WebDriver::Error::UnknownError.new('Node with given id does not belong to the document')
    Selenium::WebDriver::Element.any_instance.stubs(:displayed?).raises(error)

    Capybara.using_wait_time(0.05) do
      assert_raises(Minitest::Assertion) do
        assert_selector 'h1', text: 'Overview'
      end
    end
  end
end
