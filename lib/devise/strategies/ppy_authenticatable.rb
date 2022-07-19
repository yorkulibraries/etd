require 'devise/strategies/base'
# Devise YorkU Strategy for Passport York Authentication
module Devise
  module Strategies
    # Strategy for delegating authentication logic to custom model's method
    class PpyAuthenticatable < Base
      # it must have a `valid?` method to check if it is appropriate to use
      # for a given request
      CAS_UID = 'HTTP_PYORK_CYIN'
      CAS_USERNAME = 'HTTP_PYORK_USER' # 'HTTP_PYORK_USER'
      CAS_PYORKUSER = 'HTTP_REMOTE_USER'
      CAS_FIRST_NAME = 'HTTP_PYORK_FIRSTNAME'
      CAS_LAST_NAME = 'HTTP_PYORK_SURNAME'
      CAS_EMAIL = 'HTTP_PYORK_EMAIL'
      CAS_USER_TYPE = 'HTTP_PYORK_TYPE'

      # it must have an authenticate! method to perform the validation
      # a successful request calls `success!` with a user object to stop
      # other strategies and set up the session state for the user logged in
      # with that user object.
      def authenticate!
        value_of_credentials = valid_credentials?
        if value_of_credentials
          resource = mapping.to.find_with_authentication_profile(setup_authentication_profile)
          success!(resource)
        else
          raise(:missing_ppy_credentials)
        end
      end

      ## returns true or false if the given user is found on MyPassport
      def valid_credentials?
        # Implement logic that returns a True or False if the user's credentials are correct.
        # We'll generate a resource later, but first we need to know we're dealing with a legit request.
        # request.headers[CAS_UID].present? && request.headers[CAS_UID] != nil &&
        # request.headers[CAS_EMAIL].present? && request.headers[CAS_UID] != nil &&
        # request.headers[CAS_USERNAME].present? && request.headers[CAS_USERNAME] != nil

        !request.headers[CAS_UID].nil?
      end

      def setup_authentication_profile
        # returns some data about the user that was in the response from the Remote Authentication Service.
        # Most SSO Systems will return back a user's UniqueID, Email Address, and other attributes that can be used
        # to further refine access to resources in your Rails app.
        # user_id = request.headers[CAS_UID]
        # email = request.headers[CAS_EMAIL]
        # pyorkuser = request.headers[CAS_USERNAME]

        # patron_type = request.headers[CAS_USER_TYPE]

        {
          user_uid: request.headers[CAS_UID],
          username: request.headers[CAS_USERNAME],
          firstname: request.headers[CAS_FIRST_NAME],
          lastname: request.headers[CAS_LAST_NAME],
          user_type: request.headers[CAS_USER_TYPE],
          email_address: request.headers[CAS_EMAIL],
          pyorkuser: request.headers[CAS_PYORKUSER]
        }

        # puts '********** PROFILE I AM SENDING ***********'
        # puts profile.ai
      end
    end
  end
end

Warden::Strategies.add(:ppy_authenticatable, Devise::Strategies::PpyAuthenticatable)
