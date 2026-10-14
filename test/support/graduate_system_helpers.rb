# frozen_string_literal: true

require 'fileutils'
require 'uri'
require 'base64'

# Test-only trusted-header boundary. Mapping is one-use and restricted to /login.
# The real SessionsController and Warden PPY strategy establish the session.
class GraduateSystemPpyBoundary
  attr_accessor :login_headers

  def self.shared
    @shared ||= new(Rails.application)
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    if env['PATH_INFO'] == '/login' && env['REQUEST_METHOD'] == 'GET' && login_headers
      headers = login_headers
      self.login_headers = nil
      env = env.merge(headers)
    end
    @app.call(env)
  end
end

module GraduateSystemHelpers
  def browser_ppy_login(user)
    headers = { 'HTTP_PYORK_USER' => user.username }
    headers['HTTP_PYORK_CYIN'] = user.sisid if user.is_a?(Student)
    self.class.ppy_boundary.login_headers = headers
    visit login_path
    assert_current_path(user.is_a?(Student) ? student_view_index_path : root_path)
  end

  def browser_mock_provider(provider = 'google_oauth2', uid: 'browser-google-subject')
    OmniAuth.config.mock_auth[provider.to_sym] = OmniAuth::AuthHash.new(
      provider: provider, uid: uid, info: { email: 'synthetic-graduate@example.com' },
      extra: { raw_info: { email_verified: true } }
    )
  end

  def browser_fresh_session
    Capybara.reset_sessions!
    Warden.test_reset!
    self.class.ppy_boundary.login_headers = nil
  end

  def browser_artifact(name, mobile: false)
    current_window.resize_to(*(mobile ? [390, 844] : [1440, 1000]))
    assert_selector 'main'
    assert page.evaluate_script('document.documentElement.scrollWidth <= window.innerWidth'),
           "#{name} overflows its viewport"
    path = Rails.root.join('tmp/graduate-authentication/screenshots', "#{name}.png")
    FileUtils.mkdir_p(path.dirname)
    browser = page.driver.browser
    size = browser.execute_cdp('Page.getLayoutMetrics').fetch('cssContentSize')
    screenshot = browser.execute_cdp(
      'Page.captureScreenshot', captureBeyondViewport: true,
      clip: { x: 0, y: 0, width: size.fetch('width'), height: size.fetch('height'), scale: 1 }
    )
    File.binwrite(path, Base64.decode64(screenshot.fetch('data')))
    current_window.resize_to(1440, 1000) if mobile
  end

  def assert_required_checkbox(id)
    checkbox = find("##{id}")
    assert_equal 'true', checkbox[:required]
    refute checkbox.checked?
  end
end
