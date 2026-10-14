# frozen_string_literal: true

# Devise YorkU Strategy for Passport York Authentication
Warden::Strategies.add(:ppy_devise) do
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
    if valid?
      student = Student.find_by(sisid: request.headers[CAS_UID], role: User::STUDENT) if request.headers[CAS_UID].present?
      named_user = User.find_by(username: request.headers[CAS_USERNAME]) if request.headers[CAS_USERNAME].present?
      # PPY staff also receive CYIN. Preserve their trusted username fallback,
      # but never switch between two inconsistent known identities.
      if student && named_user && student.id != named_user.id
        fail!('Inconsistent ppy headers')
        return
      end
      resource = student || named_user
      if resource&.active?
        success!(resource)
      else
        fail!('Missing ppy headers')
      end
    else
      fail!('Missing ppy headers')
    end
  end

  ## returns true or false if the given user is found on MyPassport
  def valid?
    !request.headers[CAS_UID].nil? || !request.headers[CAS_USERNAME].nil?
  end
end
