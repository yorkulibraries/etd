# frozen_string_literal: true

require 'test_helper'

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  selenium_remote_url = "http://#{ENV.fetch('SELENIUM_SERVER')}:4444"
  
  driven_by :selenium, using: :headless_chrome do |driver_option|
    driver_option.add_argument('--disable-gpu')
    driver_option.add_argument('--no-sandbox')
    driver_option.add_argument('--disable-dev-shm-usage')

    # Add preferences
    driver_option.add_preference(:download, {
      prompt_for_download: false,
      default_directory: File.join(Rails.root, 'tmp')
    })

    # Remote driver setup
    Capybara.register_driver :selenium do |app|
      Capybara::Selenium::Driver.new(app,
        browser: :remote,
        url: selenium_remote_url,
        options: driver_option
      )
    end
  end
  
  def setup
    Capybara.server_host = "0.0.0.0"
    Capybara.app_host = "http://#{IPSocket.getaddress(Socket.gethostname)}" if ENV["SELENIUM_SERVER"].present?
    Capybara.default_max_wait_time = 5
    Capybara.save_path = "tmp/test-screenshots"
    Capybara.default_driver = :selenium

    super

    user = FactoryGirl.create(:user)
    login_as(user, role: User::STAFF)
  end

end
