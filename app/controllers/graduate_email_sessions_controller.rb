# frozen_string_literal: true
class GraduateEmailSessionsController < ApplicationController
  layout 'graduate'
  protect_from_forgery with: :exception
  skip_before_action :login_required
  skip_authorization_check
  before_action :private_response
  before_action :bounded_request
  rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_csrf

  def new
    # Starting an address transaction deliberately leaves any enrollment intent.
    session.delete(:graduate_email_intent)
    render :new
  end

  def enroll
    # Reset even for an invalid invitation. Raw token establishes no identity.
    clear_authentication_session
    browser = GraduateEmail::Challenges.browser_token!(session: session, purpose: :enroll)
    id = GraduateEmail::Enrollment.intent!(token: params[:token], browser_token: browser)
    approval = GraduateEmailApproval.find(id)
    session[:graduate_email_intent] = {'purpose' => 'enroll', 'approval_id' => id,
      'browser_token' => browser, 'expires_at' => [10.minutes.from_now.to_i, approval.expires_at.to_i].min}
    redirect_to graduate_email_verify_path
  rescue GraduateAuthentication::Rejected, ActiveRecord::ActiveRecordError
    # Clean redirect, same code screen; a bad token cannot choose login/enrollment.
    session[:graduate_email_intent] = {'purpose' => 'invalid', 'expires_at' => 10.minutes.from_now.to_i}
    redirect_to graduate_email_verify_path
  end

  def create
    intent = current_intent
    # Only this address-entry POST starts login; resend never accepts a target.
    unless session[:graduate_email_intent].present?
      browser = GraduateEmail::Challenges.browser_token!(session: session, purpose: :login)
      address = params[:address]
      address = nil unless address.is_a?(String) && address.bytesize <= 254
      intent = {'purpose' => 'login', 'address' => GraduateEmail::Address.normalize(input: address),
        'browser_token' => browser, 'expires_at' => 10.minutes.from_now.to_i}
      session[:graduate_email_intent] = intent
    end
    send_code(intent)
  end

  def resend
    send_code(current_intent)
  end

  def show
    render :verify
  end

  def verify
    intent = current_intent
    grant = GraduateEmail::Verification.redeem!(challenge_public_id: intent && intent['challenge_public_id'],
      browser_token: intent && intent['browser_token'], code: params[:code],
      ip: GraduateEmail::Limits.request_ip(request: request))
    if grant
      start_email_authentication_session(grant: grant)
      redirect_to student_view_index_path
    else
      failed_verification
    end
  rescue GraduateAuthentication::Rejected
    failed_verification
  end

  private

  def current_intent
    intent = session[:graduate_email_intent]
    return unless intent.is_a?(Hash) && intent['expires_at'].is_a?(Integer) && intent['expires_at'] > Time.current.to_i
    return intent if intent['purpose'] == 'invalid'
    return unless %w[login enroll].include?(intent['purpose']) &&
      session["graduate_email_#{intent['purpose']}_browser_token"] == intent['browser_token']
    intent
  end

  def send_code(intent)
    ip = GraduateEmail::Limits.request_ip(request: request)
    if intent && %w[login enroll].include?(intent['purpose'])
      result = GraduateEmail::Challenges.request!(purpose: intent['purpose'].to_sym,
        browser_token: intent['browser_token'], ip: ip, address: intent['address'], approval_id: intent['approval_id'])
      intent['challenge_public_id'] = result.challenge_public_id
      session[:graduate_email_intent] = intent
    end
    render :verify, status: :accepted
  end

  def failed_verification
    @verification_error = 'The code is incorrect or has expired. Request a new code and try again.'
    render :verify, status: :unprocessable_entity
  end

  def private_response
    response.set_header('Cache-Control', 'no-store')
    response.set_header('Referrer-Policy', 'no-referrer')
  end

  def bounded_request
    return head :payload_too_large if request.content_length.to_i > 2048 || request.raw_post.bytesize > 2048
    head :bad_request if Rails.env.production? && !request.ssl?
  end

  # Chromium sends Origin: null for no-referrer form POSTs. Accept this
  # privacy-preserving origin only with a valid session-bound CSRF token.
  # Every other origin still uses Rails' normal same-origin check.
  def valid_request_origin?
    return any_authenticity_token_valid? if request.origin == 'null'

    super
  end

  def invalid_csrf
    private_response
    head :unprocessable_entity
  end
end
