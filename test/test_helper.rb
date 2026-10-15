# encoding: ASCII-8BIT   # make sure this runs in binary mode
# frozen_string_literal: false

# some of the comments are in UTF-8
ENV['RAILS_ENV'] = 'test'
require_relative 'support/graduate_oauth_environment'
require File.expand_path('../config/environment', __dir__)
CarrierWave.configure do |configuration|
  configuration.root = Rails.root.join('tmp/graduate-authentication/test-uploads').to_s
end
# The guarded storage gate verifies real migrations. Rails' automatic schema
# reload would replace that database (and omit the control singleton seed).
if ENV['GRADUATE_EMAIL_PROJECT_ROOT'] && ENV['GRADUATE_EMAIL_MIGRATION_PRESERVATION'] == '1'
  ActiveRecord::Migration.check_pending!
  ActiveRecord.maintain_test_schema = false
end
require 'rails/test_help'
require 'factory_girl_rails'
require 'minitest/unit'
require 'mocha/minitest'
require 'database_cleaner/active_record'
require 'rails-controller-testing'

# Configure shoulda-matchers to use Minitest
require 'shoulda/matchers'

Rails::Controller::Testing.install

DatabaseCleaner.url_allowlist = [
  %r{.*test.*}
]
DatabaseCleaner.strategy = :truncation

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

    setup do
      if ENV['GRADUATE_EMAIL_PROJECT_ROOT']
        configuration = ActiveRecord::Base.connection_db_config.configuration_hash
        expected_database = ENV['DB_ADAPTER'] == 'sqlite3' ? Rails.root.join('tmp/graduate-email-storage_test.sqlite3').to_s : 'etd_graduate_email_test'
        unless ENV['DATABASE_URL'] == ENV['TEST_DATABASE_URL'] && configuration[:adapter] == ENV['DB_ADAPTER'] && configuration[:database] == expected_database
          raise 'Graduate email test database mismatch'
        end
      end
      ActionMailer::Base.deliveries.clear
      DatabaseCleaner.start
      AppSettings.clear_cache
    end

    teardown do
      ActionMailer::Base.deliveries.clear
      DatabaseCleaner.clean
      AppSettings.clear_cache
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
