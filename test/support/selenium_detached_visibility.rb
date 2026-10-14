# frozen_string_literal: true

require 'capybara'

# Chrome can misclassify detached-node visibility failures as unknown errors.
# Let Capybara reload the element within its existing bounded wait.
module SeleniumDetachedVisibility
  def visible?
    super
  rescue Selenium::WebDriver::Error::UnknownError => error
    raise unless error.message.include?('Node with given id does not belong to the document')

    raise Selenium::WebDriver::Error::StaleElementReferenceError, error.message
  end
end

Capybara::Selenium::ChromeNode.prepend(SeleniumDetachedVisibility)
