# frozen_string_literal: true

class Custompath < Devise::FailureApp
  def redirect
    # flash[:alert] = i18n_message unless flash[:notice]
    redirect_to invalid_login_url
    # custom redirect_to
  end
end
