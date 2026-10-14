# frozen_string_literal: true

require 'test_helper'
require_relative 'support/graduate_system_helpers'

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  class_attribute :ppy_boundary
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
    LocSubject.delete_all
    LocSubject.load_from_file('lib/loc_subjects.txt')

    Capybara.server_host = "0.0.0.0"
    Capybara.server_port = ENV.fetch("ETD_SYSTEM_TEST_PORT", "3210").to_i
    self.class.ppy_boundary = GraduateSystemPpyBoundary.shared
    Capybara.app = self.class.ppy_boundary
    Capybara.app_host = ENV["SELENIUM_REMOTE_URL"].present? ? "http://#{IPSocket.getaddress(Socket.gethostname)}:#{Capybara.server_port}" : "http://127.0.0.1:#{Capybara.server_port}"
    Capybara.default_max_wait_time = 60
    Capybara.save_path = "tmp/test-screenshots"
    Capybara.default_driver = :selenium

    super
    
    user = FactoryGirl.create(:user)
    login_as(user, role: User::STAFF)

    current_window.resize_to(1920, 1080)

    find('body', wait: Capybara.default_max_wait_time) # Ensure page is stable
  end

  # Exercise the real PPY session flow through a test-only trusted header boundary.
  def login_as(user, **_options)
    headers = { 'HTTP_PYORK_USER' => user.username }
    headers['HTTP_PYORK_CYIN'] = user.sisid if user.is_a?(Student)
    self.class.ppy_boundary.login_headers = headers
    visit login_path
    destination = if user.is_a?(Student)
                    user.theses.one? ? student_view_thesis_process_path(user.theses.first, Thesis::PROCESS_BEGIN) : student_view_index_path
                  else
                    root_path
                  end
    assert_current_path destination
  end

end
