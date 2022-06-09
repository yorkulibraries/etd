class ApplicationController < ActionController::Base
  protect_from_forgery
  check_authorization
  
  before_action :login_required   

   def current_user      
     @current_user ||= User.find_by_id(session[:user_id]) if session[:user_id]     
   end
   helper_method :current_user
   
   def logged_in?
     current_user
   end
   
   def login_required
      unless logged_in? || controller_name == "sessions"
        redirect_to login_url, :alert => "You must login before accessing this page"
      end
   end
  
  rescue_from CanCan::AccessDenied do |exception|
     redirect_to unauthorized_url, :alert => "#{exception.message}"
  end
end
