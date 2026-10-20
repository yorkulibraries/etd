# frozen_string_literal: true

class GraduateConnectionsController < ApplicationController
  before_action :private_response

  def index
    authorize! :show, :student
    raise CanCan::AccessDenied unless GraduateAuthentication.active_student?(current_user)

    @student = current_user
    @email_connection = @student.graduate_email_connections.where(revoked_at: nil).order(:id).last
    @identities = @student.graduate_identities.where(provider: GraduateAuthentication::PROVIDERS).order(:provider)
    @can_connect = GraduateAuthentication.ppy_student_session?(session, @student)
  end

  def staff_index
    load_staff_student
    @email_connection = @student.graduate_email_connections.where(revoked_at: nil).order(:id).last
    @identities = @student.graduate_identities.where(provider: GraduateAuthentication::PROVIDERS).order(:provider)
    @email_approvals = @student.graduate_email_approvals.order(created_at: :desc).limit(10)
    @invitations = @student.graduate_authentication_invitations.where(provider: GraduateAuthentication::PROVIDERS)
                          .order(created_at: :desc).limit(10)
  end

  def destroy
    if params[:student_id]
      load_staff_student
      destination = staff_student_graduate_connections_path(@student)
    else
      authorize! :show, :student
      @student = current_user
      raise CanCan::AccessDenied unless GraduateAuthentication.ppy_student_session?(session, @student)
      destination = graduate_connections_path
    end
    unless params[:confirmation] == '1'
      redirect_to destination, alert: 'Confirm that you want to remove this connection.'
      return
    end
    @student.with_lock do
      identity = @student.graduate_identities.find(params[:id])
      Audited.audit_class.as_user(current_user) { identity.destroy! }
    end
    redirect_to destination, notice: 'The sign-in connection was removed. The graduate will need Passport York or a new FGS invitation to reconnect.'
  end

  private

  def load_staff_student
    raise CanCan::AccessDenied unless GraduateAuthentication.staff_authorized?(current_user) && session[:return_to_user_id].blank?

    @student = Student.find(params[:student_id])
    authorize! :manage_graduate_authentication, @student
  end

  def private_response
    response.set_header('Cache-Control', 'no-store')
    response.set_header('Referrer-Policy', 'same-origin')
  end
end
