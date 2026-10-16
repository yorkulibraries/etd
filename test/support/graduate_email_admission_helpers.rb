# frozen_string_literal: true
require_relative 'graduate_email_helpers'

module GraduateEmailAdmissionHelpers
  def self.included(base)
    base.include GraduateEmailHelpers
  end

  def setup_admission
    @old_email_env = ENV.to_h.slice('GRADUATE_EMAIL_BASE_URL', 'GRADUATE_EMAIL_CODE_KEY', 'GRADUATE_EMAIL_LIMIT_KEY')
    ENV.update('GRADUATE_EMAIL_BASE_URL' => 'http://127.0.0.1:3210',
      'GRADUATE_EMAIL_CODE_KEY' => 'c' * 32, 'GRADUATE_EMAIL_LIMIT_KEY' => 'l' * 32)
    GraduateEmail.configure!
    GraduateEmailControl.delete_all
    GraduateEmailControl.create!(id: 1, enabled: true, generation: 1)
    @actor = create(:user, role: User::MANAGER)
    @student = create(:student)
    @connection = GraduateEmailConnection.create!(student: @student, approved_by: @actor,
      normalized_address: 'approved@example.com', verified_at: Time.current)
    @mapping = GraduateEmailActiveAddress.create!(student: @student, connection: @connection, normalized_address: @connection.normalized_address)
    @approval = GraduateEmailApproval.create!(student: @student, approved_by: @actor,
      replacement_of_connection: @connection, normalized_address: 'pending@example.com', token_digest: SecureRandom.hex(32), generation: 1, expires_at: 48.hours.from_now)
    @browser = SecureRandom.hex(32)
    @ip = '192.0.2.1'
    @instant = Time.current.change(usec: 0)
  end

  def teardown_admission
    %w[GRADUATE_EMAIL_BASE_URL GRADUATE_EMAIL_CODE_KEY GRADUATE_EMAIL_LIMIT_KEY].each { |key| ENV.delete(key) }
    ENV.update(@old_email_env || {})
    GraduateEmail.configure!
    travel_back
  end

  def request_code(**options)
    GraduateEmail::Challenges.request!(**{purpose: :login, browser_token: @browser, ip: @ip,
      address: @connection.normalized_address}.merge(options))
  end

  def challenge(result)
    GraduateEmailChallenge.find_by!(public_id: result.challenge_public_id)
  end

  # Schema-valid future delivery output, never an invented delivery API or code.
  def synthetic_sent(result)
    row = challenge(result)
    row.update!(state: 'sent', code_digest: 'd' * 64, claimed_at: Time.current,
      send_authorized_at: Time.current, sent_at: Time.current)
    row
  end

  def address_key(address = @connection.normalized_address)
    GraduateEmail::Limits.address_key(input: address)
  end

  def ip_key(ip = @ip)
    GraduateEmail::Limits.ip_key(input: ip)
  end

  def admit_verify(address: address_key, student: @student.id, ip: ip_key, now: Time.current)
    GraduateEmail::Control.synchronize do
      GraduateEmail::Limits.admit!(kind: :verify, address_key: address, student_id: student, ip_key: ip, now: now)
    end
  end

  def fail_verify(address: address_key, student: @student.id, ip: ip_key, now: Time.current)
    GraduateEmail::Control.synchronize do
      outcome = GraduateEmail::Limits.admit!(kind: :verify, address_key: address, student_id: student, ip_key: ip, now: now)
      GraduateEmail::Limits.record_failure!(address_key: address, student_id: student, ip_key: ip, now: now) if outcome == :allowed
      outcome
    end
  end

  def events(kind)
    GraduateEmailLimitEvent.where(kind: kind)
  end
end
