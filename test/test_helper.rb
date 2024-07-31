# encoding: ASCII-8BIT   # make sure this runs in binary mode
# frozen_string_literal: false

# some of the comments are in UTF-8
ENV['RAILS_ENV'] = 'test'
require File.expand_path('../config/environment', __dir__)
require 'rails/test_help'
require 'factory_girl_rails'
require 'minitest/unit'
require 'mocha/minitest'
require 'database_cleaner/active_record'
require 'capybara/rails'
require 'capybara/minitest'
require 'rails-controller-testing'

# Configure shoulda-matchers to use Minitest
require 'shoulda/matchers'
Rails::Controller::Testing.install

DatabaseCleaner.url_allowlist = [
  %r{.*test.*}
]
DatabaseCleaner.strategy = :truncation

Capybara.server_host = '0.0.0.0'
Capybara.app_host = "http://#{Socket.gethostname}:#{Capybara.server_port}"
Capybara.default_max_wait_time = 60

include ActionDispatch::TestProcess

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :minitest
    with.library :rails
  end
end

module ActiveSupport
  class TestCase
    # Setup all fixtures in test/fixtures/*.(yml|csv) for all tests in alphabetical order.
    #
    # Note: You'll currently still have to declare fixtures explicitly in integration tests
    # -- they do not yet inherit this setting

    # fixtures :all

    # Add more helper methods to be used by all tests here...
    include FactoryGirl::Syntax::Methods
    include Warden::Test::Helpers
    Warden.test_mode!

    # Make the Capybara DSL available in all integration tests
    include Capybara::DSL
    # Make `assert_*` methods behave like Minitest assertions
    include Capybara::Minitest::Assertions

    setup do
      DatabaseCleaner.start
    end

    teardown do
      Capybara.reset_sessions!
      Capybara.use_default_driver
      DatabaseCleaner.clean
    end
  end
end

module ActionController
  class TestCase
    def log_user_in(user)
      session[:user_id] = user.id unless user.blank?
    end
  end
end
