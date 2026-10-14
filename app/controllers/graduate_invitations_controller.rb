# frozen_string_literal: true

class GraduateInvitationsController < ApplicationController
  def create
    raise CanCan::AccessDenied unless GraduateAuthentication.staff_authorized?(current_user) && session[:return_to_user_id].blank?

    @student = Student.find(params[:student_id])
    authorize! :manage_graduate_authentication, @student
    response.set_header('Cache-Control', 'no-store')
    response.set_header('Referrer-Policy', 'no-referrer')
    raise GraduateAuthentication::Rejected unless params[:identity_verified] == '1'

    token = nil
    Audited.audit_class.as_user(current_user) do
      @invitation, token = GraduateAuthenticationInvitation.issue!(student: @student, approved_by: current_user,
                                                                 provider: params[:provider])
    end
    @invitation_url = "#{GraduateAuthentication.base_url}#{graduate_enroll_path}?#{URI.encode_www_form(token: token)}"
    render :created
  rescue GraduateAuthentication::Rejected, ActiveRecord::RecordInvalid
    redirect_to staff_student_graduate_connections_path(@student),
                alert: 'Verify this active student’s identity outside this application and confirm verification before creating an invitation. Choose an available provider.'
  end
end
