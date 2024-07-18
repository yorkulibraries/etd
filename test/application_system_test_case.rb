# frozen_string_literal: true

require 'test_helper'

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400], options: {
    browser: :remote,
    url: "http://#{ENV.fetch('SELENIUM_SERVER')}:4444"
  }

  def setup
    user = FactoryGirl.create(:user)
    login_as(user)
  end

  Capybara.save_path = "tmp/test-screenshots"
end
