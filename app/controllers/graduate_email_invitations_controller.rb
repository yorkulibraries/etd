# frozen_string_literal: true
class GraduateEmailInvitationsController < ApplicationController
  protect_from_forgery with: :exception
  before_action :staff_student

  def create
    approval, token = GraduateEmail::Enrollment.issue!(student: @student, actor: current_user,
      address: params[:address], confirmed_address: params[:confirmed_address],
      identity_verified: params[:identity_verified] == '1', impersonating: session[:return_to_user_id].present?, replacement: params[:replacement] == '1')
    @invitation_url = "#{GraduateEmail.base_url}#{graduate_email_enroll_path}?#{URI.encode_www_form(token: token)}"
    render :created
  rescue GraduateAuthentication::Rejected, ActiveRecord::ActiveRecordError
    redirect_to staff_student_graduate_connections_path(@student),
      alert: 'Confirm one supported address and complete the FGS identity check for this active student.'
  end

  def destroy
    approval = GraduateEmailApproval.find_by(id: request.path_parameters[:id], student_id: @student.id)
    raise GraduateAuthentication::Rejected unless approval
    GraduateEmail::Revocation.approval!(approval: approval, actor: current_user, impersonating: session[:return_to_user_id].present?)
    redirect_to staff_student_graduate_connections_path(@student), notice: 'The pending email invitation was canceled.'
  rescue GraduateAuthentication::Rejected, ActiveRecord::ActiveRecordError
    redirect_to staff_student_graduate_connections_path(@student), alert: 'The email invitation could not be changed.'
  end

  private

  def staff_student
    response.set_header('Cache-Control', 'no-store')
    response.set_header('Referrer-Policy', 'no-referrer')
    return head :bad_request if Rails.env.production? && !request.ssl?
    raise CanCan::AccessDenied unless GraduateAuthentication.staff_authorized?(current_user) && !current_user.is_a?(Student) && session[:return_to_user_id].blank?
    @student = Student.find(request.path_parameters[:student_id])
    authorize! :manage_graduate_authentication, @student
    head :payload_too_large if request.content_length.to_i > 2048 || request.raw_post.bytesize > 2048
  end
end
