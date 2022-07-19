class SessionsController < ApplicationController
  before_action :authenticate_user!

  def new
    if current_user && current_user.is_a?(Student)
      redirect_to student_view_index_url, notice: 'Logged In!'
    elsif current_user
      redirect_to root_url, notice: 'Logged in!'
    else
      redirect_to invalid_login_url, alert: 'Invalid username or password'
    end
  end

  def invalid_login
    render layout: 'simple'
  end

  def destroy
    session[:user_id] = nil

    cookies.delete('mayaauth', domain: 'yorku.ca')
    cookies.delete('pybpp', domain: 'yorku.ca')

    redirect_to 'http://www.library.yorku.ca', allow_other_host: true
  end
end
