# frozen_string_literal: true

class SessionsController < ApplicationController
  before_action :authenticate_user!, except: :destroy
  skip_authorization_check

  def new
    current_user = request.env['warden'].authenticate!
    session[:user_id] = current_user.id if current_user
    if current_user.is_a?(Student)
      if current_user.username == current_user.sisid && request.headers['HTTP_PYORK_USER']
        current_user.update_attribute(:username,
                                      request.headers['HTTP_PYORK_USER'])
      end
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
    request.env['warden'] = nil if request.env['warden'].present?

    cookies.delete('mayaauth', domain: 'yorku.ca')
    cookies.delete('pybpp', domain: 'yorku.ca')

    redirect_to 'http://www.library.yorku.ca', allow_other_host: true
  end
end
