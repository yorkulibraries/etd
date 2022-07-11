class SessionsController < ApplicationController
  skip_authorization_check

  def new
    if Rails.env.development?
      @username = if params[:as].nil?
                    User::ADMIN
                  else
                    params[:as]
                  end
    else
      @username = request.headers['HTTP_PYORK_USER']
      @username_alt = request.headers['HTTP_PYORK_CYIN']
    end

    users = User.active.where('username = ? OR sisid = ?', @username, @username_alt)
    if users.size == 1

      user = users.first

      session[:user_id] = user.id
      if user.is_a? Student

        # update the username, if it is not set

        if user.username == user.sisid && request.headers['HTTP_PYORK_USER']
          user.update_attribute(:username, request.headers['HTTP_PYORK_USER'])
        end

        redirect_to student_view_index_url, notice: 'Logged In!'
      else
        redirect_to root_url, notice: 'Logged in!'
      end
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
