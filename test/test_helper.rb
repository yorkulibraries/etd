# encoding: ASCII-8BIT   # make sure this runs in binary mode
# frozen_string_literal: false

# some of the comments are in UTF-8
ENV['RAILS_ENV'] = 'test'
require File.expand_path('../config/environment', __dir__)
require 'rails/test_help'
require 'factory_girl_rails'
require 'mocha/setup'
include ActionDispatch::TestProcess

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.(yml|csv) for all tests in alphabetical order.
  #
  # Note: You'll currently still have to declare fixtures explicitly in integration tests
  # -- they do not yet inherit this setting

  # fixtures :all

  # Add more helper methods to be used by all tests here...
  include FactoryGirl::Syntax::Methods
  include Warden::Test::Helpers
  Warden.test_mode!
end

class ActionController::TestCase
  def log_user_in(user)
    session[:user_id] = user.id unless user.blank?
  end
end
