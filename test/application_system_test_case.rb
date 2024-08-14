# frozen_string_literal: true

require 'test_helper'

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400] do |options|
    options.add_argument('--disable-gpu')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')

    # Add preferences
    options.add_preference(:download, {
      prompt_for_download: false,
      default_directory: File.join(Rails.root, 'tmp')
    })

    # Remote driver setup
    Capybara.register_driver :selenium do |app|
      Capybara::Selenium::Driver.new(app,
        browser: :remote,
        url: "http://#{ENV.fetch('SELENIUM_SERVER')}:4444",
        options: options
      )
    end
  end

  def setup
    user = FactoryGirl.create(:user)
    login_as(user)
  end

  Capybara.save_path = "tmp/test-screenshots"
end
