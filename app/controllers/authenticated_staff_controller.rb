class AuthenticatedStaffController < ApplicationController
  before_action :redirect_if_not_staff

  private
  def redirect_if_not_staff
    if current_user.role == User::STUDENT
      redirect_to unauthorized_url, alert: "You are not allowed to view this page"
    end
  end
end
