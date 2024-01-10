# frozen_string_literal: true

class AuthenticatedStaffController < ApplicationController
  before_action :redirect_if_not_staff

  private

  def redirect_if_not_staff
    redirect_to unauthorized_url, alert: 'You are not allowed to view this page' if current_user.role == User::STUDENT
  end
end
