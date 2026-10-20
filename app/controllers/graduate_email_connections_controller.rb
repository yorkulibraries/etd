# frozen_string_literal: true
class GraduateEmailConnectionsController < ApplicationController
  protect_from_forgery with: :exception
  before_action :staff_student
  rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_csrf

  def destroy
    raise GraduateAuthentication::Rejected unless params[:confirmation] == '1'
    connection = @student.graduate_email_connections.find_by(id: request.path_parameters[:id])
    raise GraduateAuthentication::Rejected unless connection
    GraduateEmail::Revocation.connection!(connection: connection, actor: current_user,
      impersonating: session[:return_to_user_id].present?)
    redirect_to staff_student_graduate_connections_path(@student), notice: 'The email sign-in connection was removed. FGS must approve a new invitation to restore email access.'
  rescue GraduateAuthentication::Rejected, ActiveRecord::ActiveRecordError
    redirect_to staff_student_graduate_connections_path(@student), alert: 'Confirm removal of this student’s email connection. The connection could not be changed.'
  end

  private

  def private_response
    response.set_header('Cache-Control', 'no-store')
    response.set_header('Referrer-Policy', 'no-referrer')
  end

  def invalid_csrf
    private_response
    head :unprocessable_entity
  end

  def staff_student
    private_response
    return head :bad_request if Rails.env.production? && !request.ssl?
    raise CanCan::AccessDenied unless GraduateEmail::Enrollment.authorized?(current_user) && session[:return_to_user_id].blank?
    @student = Student.find(request.path_parameters[:student_id])
    authorize! :manage_graduate_authentication, @student
    head :payload_too_large if request.content_length.to_i > 2048 || request.raw_post.bytesize > 2048
  end
end
