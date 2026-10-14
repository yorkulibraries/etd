# frozen_string_literal: true

require 'test_helper'
require_relative '../support/graduate_system_helpers'
require 'digest'
require 'timeout'

class GraduateDownloadsSystemTest < ActionDispatch::SystemTestCase
  include GraduateSystemHelpers
  class_attribute :ppy_boundary

  driven_by :selenium, using: :headless_chrome, screen_size: [1440, 1000] do |options|
    chrome_binary = ENV['CHROME_BIN'].presence || ('/usr/bin/chromium' if File.executable?('/usr/bin/chromium'))
    options.binary = chrome_binary if chrome_binary
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--disable-gpu')
    options.add_preference(:download, prompt_for_download: false, default_directory: Rails.root.join('tmp/graduate-authentication/download-artifacts').to_s)
  end

  setup do
    @previous_capybara_settings = {
      app: Capybara.app, server_host: Capybara.server_host, server_port: Capybara.server_port,
      app_host: Capybara.app_host, default_max_wait_time: Capybara.default_max_wait_time,
      save_path: Capybara.save_path
    }
    self.class.ppy_boundary = GraduateSystemPpyBoundary.shared
    Capybara.app = self.class.ppy_boundary
    Capybara.server_host = '127.0.0.1'
    Capybara.server_port = ENV.fetch("ETD_SYSTEM_TEST_PORT", "3210").to_i
    Capybara.app_host = "http://127.0.0.1:#{Capybara.server_port}"
    Capybara.default_max_wait_time = 5
    Capybara.save_path = Rails.root.join('tmp/graduate-authentication/screenshots').to_s
    ActionDispatch::SystemTesting::Server.new.run
    @forgery = ActionController::Base.allow_forgery_protection
    @app_forgery = ApplicationController.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    ApplicationController.allow_forgery_protection = true
    OmniAuth.config.test_mode = true
    browser_mock_provider
    Warden.test_reset!
  end

  teardown do
    self.class.ppy_boundary.login_headers = nil
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
    ActionController::Base.allow_forgery_protection = @forgery
    ApplicationController.allow_forgery_protection = @app_forgery
    FileUtils.rm_rf(@upload_directory) if @upload_directory
    Warden.test_reset!
  end

  def after_teardown
    super
  ensure
    @previous_capybara_settings&.each { |setting, value| Capybara.public_send("#{setting}=", value) }
  end

  test 'graduate clicks authorized download and receives repeatable file artifact' do
    student = create(:student, name: 'Synthetic Download Graduate')
    browser_ppy_login(student)
    visit graduate_connections_path
    click_button 'Connect Google'
    assert_current_path graduate_connections_path
    thesis = create(:thesis, student: student, title: 'Synthetic Download Thesis', degree_name: 'PhD', exam_date: Date.new(2026, 1, 1))
    document = create(:document, thesis: thesis, user: student, supplemental: false,
                      file: Rack::Test::UploadedFile.new('test/fixtures/files/pdf-document.pdf', 'application/pdf'))
    @upload_directory = File.dirname(document.file.path)
    browser_fresh_session
    visit graduate_login_path
    click_button 'Continue with Google'
    assert_current_path student_view_thesis_process_path(thesis, Thesis::PROCESS_BEGIN)
    visit student_view_thesis_process_path(thesis, Thesis::PROCESS_UPLOAD)
    assert_link 'Download', href: download_student_thesis_document_path(student, thesis, document)
    assert_no_link href: document.file_url
    browser_artifact('download-desktop')
    directory = Rails.root.join('tmp/graduate-authentication/download-artifacts')
    FileUtils.mkdir_p(directory)
    # The WebDriver may be shared with another system class whose preferences
    # were set first. Set the actual browser's download destination explicitly.
    page.driver.browser.execute_cdp('Browser.setDownloadBehavior', behavior: 'allow', downloadPath: directory.to_s)
    downloaded = directory.join(File.basename(document.file.path))
    FileUtils.rm_f(downloaded)
    click_link 'Download'
    Timeout.timeout(10) { sleep 0.05 until File.file?(downloaded) }
    digest = Digest::SHA256.file(downloaded).hexdigest
    assert_equal Digest::SHA256.file(Rails.root.join('test/fixtures/files/pdf-document.pdf')).hexdigest, digest
    File.write(directory.join('download-sha256.txt'), "#{digest}  #{downloaded.basename}\n")
  end
end
