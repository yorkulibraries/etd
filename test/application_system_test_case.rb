# frozen_string_literal: true

require 'test_helper'

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  options = ENV["SELENIUM_REMOTE_URL"].present? ? { browser: :remote, url: ENV["SELENIUM_REMOTE_URL"] } : nil
  driven_by :selenium, using: :headless_chrome, options: options do |driver_option|
    driver_option.add_argument('--disable-gpu')
    driver_option.add_argument('--no-sandbox')
    driver_option.add_argument('--disable-dev-shm-usage')

    # Add preferences
    driver_option.add_preference(:download, {
      prompt_for_download: false,
      default_directory: File.join(Rails.root, 'tmp')
    })
  end
  
  def setup
    Capybara.server_host = "0.0.0.0"
    Capybara.app_host = "http://#{IPSocket.getaddress(Socket.gethostname)}" if ENV["SELENIUM_REMOTE_URL"].present?
    Capybara.default_max_wait_time = 30
    Capybara.save_path = "tmp/test-screenshots"
    Capybara.default_driver = :selenium

    super

    current_window.resize_to(1920, 1080)
    
    user = FactoryGirl.create(:user)
    login_as(user, role: User::STAFF)
  end

end
