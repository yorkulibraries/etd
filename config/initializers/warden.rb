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
      resource = User.find_by('sisid = ? OR username = ?', request.headers[CAS_UID], request.headers[CAS_USERNAME])
      success!(resource)
    else
      fail!('Missing ppy headers')
    end
  end

  ## returns true or false if the given user is found on MyPassport
  def valid?
    !request.headers[CAS_UID].nil? || !request.headers[CAS_USERNAME].nil?
  end
end
