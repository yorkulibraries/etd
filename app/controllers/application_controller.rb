# frozen_string_literal: true

class ApplicationController < ActionController::Base
  protect_from_forgery
  check_authorization

  before_action :login_required

  def current_user
    @current_user ||= User.find_by_id(session[:user_id]) if session[:user_id]
  end
  helper_method :current_user

  def login_required
    return if current_user || controller_name == 'sessions'

    redirect_to login_url
  end

  rescue_from CanCan::AccessDenied do |exception|
    redirect_to unauthorized_url, alert: exception.message.to_s
  end
end
