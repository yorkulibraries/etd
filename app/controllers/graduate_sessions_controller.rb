# frozen_string_literal: true

class GraduateSessionsController < ApplicationController
  layout 'graduate'
  skip_before_action :login_required
  skip_authorization_check
  before_action :private_response

  def new
    @enrollment = valid_enrollment.present?
    @providers = @enrollment ? [valid_enrollment.provider] : GraduateAuthentication.enabled_providers
  end

  def enroll
    session.delete(:graduate_enrollment)
    session.delete(:graduate_oauth_intent)
    invitation = GraduateAuthenticationInvitation.for_token(params[:token])
    unless invitation&.usable? && GraduateAuthentication.enabled_providers.include?(invitation.provider)
      flash.now[:alert] = 'This invitation is unavailable or has expired. Contact FGS for a new invitation.'
      @providers = GraduateAuthentication.enabled_providers
      render :new, status: :unprocessable_entity
      return
    end

    # A token establishes enrollment intent only, never a student session.
    clear_authentication_session
    session[:graduate_enrollment] = { 'invitation_id' => invitation.id,
                                     'expires_at' => GraduateAuthentication::INTENT_LIFETIME.from_now.to_i }
    redirect_to graduate_login_path
  end

  def callback
    provider = params[:provider]
    return unavailable unless GraduateAuthentication.enabled_providers.include?(provider)

    intent = session.delete(:graduate_oauth_intent)
    uid = GraduateAuthentication.verified_subject!(request.env, provider)
    raise GraduateAuthentication::Rejected unless intent && intent['provider'] == provider &&
                                                intent['expires_at'].to_i > Time.current.to_i

    case intent['mode']
    when 'link'
      student = current_user
      raise GraduateAuthentication::Rejected unless GraduateAuthentication.ppy_student_session?(session, student) &&
                                                  student.id == intent['student_id']
      identity = nil
      student.with_lock do
        raise GraduateAuthentication::Rejected unless GraduateAuthentication.active_student?(student)
        Audited.audit_class.as_user(student) do
          identity = student.graduate_identities.create!(provider: provider, uid: uid, linked_by: student, link_method: 'ppy')
        end
      end
      start_authentication_session(student, source: 'ppy')
      redirect_to graduate_connections_path, notice: "#{GraduateAuthentication.label(provider)} is connected."
    when 'invitation'
      invitation = GraduateAuthenticationInvitation.find_by(id: intent['invitation_id'])
      enrollment = session.delete(:graduate_enrollment)
      raise GraduateAuthentication::Rejected unless invitation && enrollment &&
                                                  enrollment['invitation_id'] == invitation.id &&
                                                  enrollment['expires_at'].to_i > Time.current.to_i
      student = invitation.student
      identity = nil
      student.with_lock do
        invitation.reload.lock!
        raise GraduateAuthentication::Rejected unless invitation.usable? && invitation.provider == provider
        Audited.audit_class.as_user(invitation.approved_by) do
          identity = student.graduate_identities.create!(provider: provider, uid: uid,
                                                       linked_by: invitation.approved_by, link_method: 'invitation')
          invitation.update!(consumed_at: Time.current)
        end
        start_authentication_session(student, source: 'graduate_oauth', identity: identity)
      end
      redirect_to student_view_index_path, notice: 'Your graduate sign-in is connected.'
    when 'login'
      identity = GraduateIdentity.find_by(provider: provider, uid: uid)
      raise GraduateAuthentication::Rejected unless identity && GraduateAuthentication.active_student?(identity.student)

      student = identity.student
      student.with_lock do
        identity.reload
        raise GraduateAuthentication::Rejected unless GraduateAuthentication.active_student?(student) &&
                                                    identity.student_id == student.id

        start_authentication_session(student, source: 'graduate_oauth', identity: identity)
      end
      redirect_to student_view_index_path
    else
      raise GraduateAuthentication::Rejected
    end
  rescue GraduateAuthentication::Rejected, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique,
         ActiveRecord::RecordNotFound
    failed_sign_in
  end

  def failure
    failed_sign_in
  end

  def unavailable
    GraduateAuthentication.clear_transaction!(session)
    session.delete(:graduate_oauth_intent)
    session.delete(:graduate_enrollment)
    @providers = []
    flash.now[:alert] = 'This sign-in option is unavailable. Use Passport York or contact FGS for help.'
    render :new, status: :not_found
  end

  private

  def private_response
    response.set_header('Cache-Control', 'no-store')
    response.set_header('Referrer-Policy', action_name == 'enroll' ? 'no-referrer' : 'same-origin')
  end

  def valid_enrollment
    enrollment = session[:graduate_enrollment]
    return unless enrollment && enrollment['expires_at'].to_i > Time.current.to_i

    invitation = GraduateAuthenticationInvitation.find_by(id: enrollment['invitation_id'])
    invitation if invitation&.usable? && GraduateAuthentication.enabled_providers.include?(invitation.provider)
  end

  def failed_sign_in
    session.delete(:graduate_oauth_intent)
    session.delete(:graduate_enrollment)
    redirect_to graduate_login_path, alert: GraduateAuthentication::FAILURE_MESSAGE
  end
end
