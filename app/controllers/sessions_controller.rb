# frozen_string_literal: true

class SessionsController < ApplicationController
  skip_authorization_check
  prepend_before_action :remember_graduate_logout, only: :destroy

  def new
    # Drop cached Warden authentication, then use only fresh PPY header proof.
    clear_authentication_session
    ppy_user = request.env['warden'].authenticate(:ppy_devise, scope: :user)
    if ppy_user&.active?
      start_authentication_session(ppy_user, source: 'ppy')
    end
    if ppy_user.is_a?(Student) && ppy_user.active?
      if ppy_user.username == ppy_user.sisid && request.headers['HTTP_PYORK_USER']
        ppy_user.update_attribute(:username, request.headers['HTTP_PYORK_USER'])
      end
      redirect_to student_view_index_url
    elsif ppy_user&.active?
      redirect_to root_url
    else
      redirect_to invalid_login_url, alert: 'Invalid username or password'
    end
  end

  def invalid_login
    render layout: 'simple'
  end

  def destroy
    external = @graduate_logout
    clear_authentication_session

    if external
      redirect_to graduate_login_path
      return
    end

    cookies.delete('mayaauth', domain: 'yorku.ca')
    cookies.delete('pybpp', domain: 'yorku.ca')

    redirect_to 'https://passportyork.yorku.ca/ppylogin/ppylogout', allow_other_host: true
  end

  private

  def remember_graduate_logout
    @graduate_logout = GraduateSession.marked?(session)
  end
end
