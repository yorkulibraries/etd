require 'devise/strategies/ppy_authenticatable'

# lib/devise/models/ppy_authenticatable.rb
# PpyAuthenticatable Model to find user account or create if new
module Devise::Models
  module PpyAuthenticatable
    extend ActiveSupport::Concern

    class_methods do
      # defining a class method that can find or create a Resource record
      # and returns it back to our Authentication Strategy
      #
      # If a user needs to sign up first,
      #   with Registerable, merely look up the record in your database
      #   instead of creating a new one
      def find_with_authentication_profile(profile)
        find_by(sisid: profile[:user_uid])
      end
    end
  end
end
