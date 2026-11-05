# frozen_string_literal: true

require 'selenium-webdriver'

# Chrome can label a detached element as an unknown error in any operation.
# Keep Capybara's normal stale-element reload and bounded retry behavior.
module SeleniumDetachedElementErrors
  def error
    original = super
    return original unless original.is_a?(Selenium::WebDriver::Error::UnknownError) &&
                           original.message.include?('Node with given id does not belong to the document')

    stale = Selenium::WebDriver::Error::StaleElementReferenceError.new(original.message)
    stale.set_backtrace(original.backtrace)
    stale
  end
end

Selenium::WebDriver::Remote::Response.prepend(SeleniumDetachedElementErrors)
