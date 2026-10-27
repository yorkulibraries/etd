# frozen_string_literal: true
class GraduateEmailInvitationsController < ApplicationController
  # Server-side review of the normalized recipient. Only the latest review in
  # this staff session can issue, once, for the same student, actor and mode.
  REVIEW_KEY = 'graduate_email_review'
  REVIEW_LIFETIME = 15.minutes
  CONFLICTS = %i[active_elsewhere pending_elsewhere].freeze
  MESSAGES = {
    unsupported: ['Enter one individual email address in a supported format.',
      'Lists, display names, spaces, quoted addresses and international domain names are not supported.'],
    mismatch: ['The two address entries do not match.', 'Enter the same individual address in both fields.'],
    active_elsewhere: ['This address is already the verified email sign-in address of another student record.',
      'ETD allows one student record per sign-in address. Check whether the records are duplicates or the mailbox is shared. ' \
      'Each graduate needs an individual mailbox. Remove the other record’s email connection only after FGS confirms it is wrong.'],
    pending_elsewhere: ['This address already has a pending email invitation for another student record.',
      'Check whether the records are duplicates or the mailbox is shared. If FGS confirms that this student owns the mailbox, ' \
      'cancel the other record’s pending invitation and review the address again. Otherwise choose a different individual address.'],
    state_changed: ['This student’s email sign-in changed since the page was loaded.',
      'Return to the graduate connections page and start again.'],
    stale: ['This address review is no longer current. No invitation was created.',
      'Review the address again before creating the invitation.'],
    confirmation: ['Confirm the FGS identity check and the exact address before creating the invitation.', nil],
    unavailable: ['Email invitations are unavailable right now. No invitation was created.',
      'Try again later. If this continues, contact the ETD administrator.']
  }.freeze

  protect_from_forgery with: :exception
  before_action :staff_student
  rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_csrf

  def review
    session.delete(REVIEW_KEY)
    @replacement = params[:replacement] == '1'
    result = GraduateEmail::Enrollment.review(student: @student, actor: current_user, address: params[:address],
      confirmed_address: params[:confirmed_address], replacement: @replacement)
    return review_error(result.reason, other_student_id: result.other_student_id) if result.reason

    @address = result.address
    session[REVIEW_KEY] = {'student_id' => @student.id, 'actor_id' => current_user.id, 'address' => @address,
      'replacement' => @replacement, 'expires_at' => REVIEW_LIFETIME.from_now.to_i}
    render_review
  rescue GraduateAuthentication::Rejected, ActiveRecord::ActiveRecordError
    review_error(:unavailable)
  end

  def create
    @replacement = params[:replacement] == '1'
    reviewed = session[REVIEW_KEY]
    unless current_review?(reviewed)
      session.delete(REVIEW_KEY)
      return review_error(:stale)
    end
    @address = reviewed['address']
    unless params[:identity_verified] == '1' && params[:address_confirmed] == '1'
      @review_error = :confirmation
      return render_review(:unprocessable_entity)
    end

    session.delete(REVIEW_KEY)
    @approval, token = GraduateEmail::Enrollment.issue!(student: @student, actor: current_user,
      address: @address, confirmed_address: params[:reviewed_address], identity_verified: true,
      impersonating: session[:return_to_user_id].present?, replacement: @replacement)
    @invitation_url = "#{GraduateEmail.base_url}#{graduate_email_enroll_path}?#{URI.encode_www_form(token: token)}"
    render :created
  rescue GraduateEmail::Enrollment::Refused => error
    review_error(error.reason, other_student_id: error.other_student_id)
  rescue GraduateAuthentication::Rejected, ActiveRecord::ActiveRecordError
    review_error(:unavailable)
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

  def current_review?(reviewed)
    reviewed.is_a?(Hash) && reviewed['student_id'] == @student.id && reviewed['actor_id'] == current_user.id &&
      reviewed['replacement'] == @replacement && reviewed['expires_at'].is_a?(Integer) &&
      reviewed['expires_at'] > Time.current.to_i && reviewed['address'].is_a?(String) &&
      params[:reviewed_address].is_a?(String) && reviewed['address'] == params[:reviewed_address]
  end

  # Fixed staff copy only. The other record is linked, never described, and
  # only when this staff member may manage it.
  def review_error(reason, other_student_id: nil)
    @review_error = MESSAGES.key?(reason) ? reason : :unavailable
    @address = nil
    other = Student.find_by(id: other_student_id) if CONFLICTS.include?(@review_error) && other_student_id
    @other_student = other if other && can?(:manage_graduate_authentication, other)
    render_review(CONFLICTS.include?(@review_error) ? :conflict : :unprocessable_entity)
  end

  # Review pages hold forms but never a token. Chromium sends Origin: null for
  # POSTs from a no-referrer page, so keep same-origin here (as on the staff
  # connections page) and Rails' normal origin check. The token page stays no-referrer.
  def render_review(status = :ok)
    response.set_header('Referrer-Policy', 'same-origin')
    render :review, status: status
  end

  def invalid_csrf
    response.set_header('Cache-Control', 'no-store')
    response.set_header('Referrer-Policy', 'no-referrer')
    head :unprocessable_entity
  end

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
