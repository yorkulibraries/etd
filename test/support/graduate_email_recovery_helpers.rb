# frozen_string_literal: true
require_relative 'graduate_email_flow_helpers'

module GraduateEmailRecoveryHelpers
  def self.included(base)
    base.include GraduateEmailFlowHelpers
  end

  def prepare_replacement(student: @student, address: 'replacement@example.com')
    approval, token = issue_approval(student: student, address: address, replacement: true)
    browser = SecureRandom.hex(32)
    row = challenge(GraduateEmail::Challenges.request!(purpose: :enroll, approval_id: approval.id,
      browser_token: browser, ip: @ip))
    deliver_row(row)
    code = otp_code_for(public_id: row.public_id)
    assert code.is_a?(String), 'Replacement code captured only in RAM'
    [approval, token, row, browser, code]
  end

  def recovery_redeem(data)
    redeem(data[2], browser: data[3], code: data[4])
  end

  def email_session(connection = @connection)
    GraduateEmail::Control.synchronize do |control|
      GraduateSession.issue_email!(connection: connection, generation: control.generation)
    end
  end

  def valid_email?(token, connection = @connection)
    GraduateSession.valid_for?(token, method: 'email', email_connection_id: connection.id,
      generation: 1, student_id: connection.student_id)
  end

  def fill_notice_queue(count)
    count.times do |index|
      job = Delayed::Job.enqueue(GraduateEmailNoticeJob.new(1), queue: 'graduate_email_notice')
      job.update_columns(locked_at: Time.current, locked_by: 'synthetic', failed_at: index.even? ? Time.current : nil)
    end
  end
end
