# frozen_string_literal: true
require_relative 'graduate_email_delivery_helpers'

module GraduateEmailFlowHelpers
  def self.included(base)
    base.include GraduateEmailDeliveryHelpers
  end

  def setup_flow
    setup_delivery
    @approval.destroy!
    @mapping.destroy!
    @connection.destroy!
    @approval = @mapping = @connection = nil
  end

  def issue_approval(student: @student, address: 'approved@example.com', **options)
    GraduateEmail::Enrollment.issue!(student: student, actor: @actor, address: address,
      confirmed_address: address.upcase, identity_verified: true, impersonating: false, **options)
  end

  def enrolled_connection
    @connection = GraduateEmailConnection.create!(student: @student, approved_by: @actor,
      normalized_address: 'approved@example.com', verified_at: Time.current)
    @mapping = GraduateEmailActiveAddress.create!(student: @student, connection: @connection,
      normalized_address: @connection.normalized_address)
    @connection
  end

  def sent_enrollment
    @approval, @token = issue_approval
    @browser = SecureRandom.hex(32)
    @row = challenge(GraduateEmail::Challenges.request!(purpose: :enroll, browser_token: @browser,
      ip: @ip, approval_id: @approval.id))
    deliver_row(@row)
    @code = otp_code_for(public_id: @row.public_id)
    assert @code.is_a?(String), 'RAM transport captured code'
    @row
  end

  def redeem(row = @row, browser: @browser, code: @code, ip: @ip)
    GraduateEmail::Verification.redeem!(challenge_public_id: row&.public_id,
      browser_token: browser, code: code, ip: ip)
  end
end
