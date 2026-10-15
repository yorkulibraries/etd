# frozen_string_literal: true

class ApplicationController < ActionController::Base
  protect_from_forgery
  check_authorization

  before_action :login_required

  def current_user
    # Cache only within this request; blocking and revocation are checked next request.
    return @current_user if defined?(@current_user)

    @current_user = session[:user_id] ? User.find_by_id(session[:user_id]) : nil
    if (session[:user_id] || GraduateSession.marked?(session)) &&
       !valid_authentication_session?(@current_user)
      clear_authentication_session
    end
    @current_user
  end
  helper_method :current_user

  def login_required
    return if current_user || controller_name == 'sessions'

    redirect_to GraduateAuthentication.available? ? graduate_login_path : login_url
  end

  rescue_from CanCan::AccessDenied do |exception|
    redirect_to unauthorized_url, alert: exception.message.to_s
  end

  protected

  def clear_authentication_session
    GraduateSession.revoke(session[:graduate_session_token])
    request.env['warden']&.logout
    reset_session
    @current_user = nil
  end

  def start_authentication_session(user, source:, identity: nil)
    clear_authentication_session
    if source == 'graduate_oauth'
      raise GraduateAuthentication::Rejected unless GraduateAuthentication.active_student?(user) &&
                                                    identity&.persisted? && identity.student_id == user.id

      token = GraduateSession.issue!(identity)
    end
    request.env['warden']&.set_user(user, scope: :user)
    session[:user_id] = user.id
    session[:auth_source] = source
    if token
      session[:graduate_identity_id] = identity.id
      session[:graduate_session_token] = token
    end
    @current_user = user
  end

  def start_email_authentication_session(grant:)
    raise GraduateAuthentication::Rejected unless grant.is_a?(GraduateEmail::Grant) &&
      ActiveRecord::Base.connection.open_transactions.zero?

    user = Student.find_by(id: grant.student_id)
    raise GraduateAuthentication::Rejected unless grant.authentication_method == 'email' &&
      GraduateSession.valid_for?(grant.session_token, email_connection_id: grant.connection_id,
        generation: grant.generation, method: 'email', student_id: grant.student_id)

    clear_authentication_session
    request.env['warden']&.set_user(user, scope: :user)
    session[:user_id] = user.id
    session[:auth_source] = 'graduate_email'
    session[:graduate_email_connection_id] = grant.connection_id
    session[:graduate_email_generation] = grant.generation
    session[:graduate_session_token] = grant.session_token
    @current_user = user
    nil
  end

  def valid_external_identity?(user)
    return true unless GraduateSession.marked?(session)

    GraduateSession.valid_markers_for?(session, user)
  end

  def valid_authentication_session?(user)
    if session[:return_to_user_id].blank?
      return user&.active? && valid_external_identity?(user)
    end

    # Existing signed support sessions can lack auth_source. Recheck the staff
    # actor each request, while keeping impersonation separate from OAuth login.
    return false unless user.is_a?(Student) && user.role == User::STUDENT
    return false if GraduateSession.marked?(session)

    actor = User.find_by(id: session[:return_to_user_id])
    actor&.active? && !actor.is_a?(Student) && [User::ADMIN, User::MANAGER, User::STAFF].include?(actor.role)
  end
end
