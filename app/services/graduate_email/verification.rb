# frozen_string_literal: true
module GraduateEmail
  module Verification
    def self.redeem!(challenge_public_id:, browser_token:, code:, ip:)
      Control.synchronize do |control|
        now = Time.current
        ip_key = Limits.ip_key(input: ip)
        preflight = Limits.verify_admission(ip_key: ip_key, now: now)
        next nil if preflight == :capacity
        # Even malformed/cross-browser/reused attempts reach global/IP admission.
        # IDs here are selected only from the controller's signed transaction.
        hint = if preflight == :allowed && challenge_public_id.is_a?(String) && Delivery::FORMAT.match?(challenge_public_id)
          GraduateEmailChallenge.find_by(public_id: challenge_public_id)
        end
        row = hint && Delivery.eligible_challenge_locked!(challenge_public_id: hint.public_id,
          states: %w[sending sent], now: now)
        bound = begin
          hint && %w[enroll login].include?(hint.purpose) &&
            ActiveSupport::SecurityUtils.fixed_length_secure_compare(hint.browser_digest,
              Challenges.browser_digest(browser_token: browser_token, purpose: hint.purpose.to_sym))
        rescue GraduateAuthentication::Rejected, ArgumentError
          false
        end
        # Terminal rows contribute only to limits; no state can be revived.
        address_key = bound ? hint.address_key : nil
        student_id = bound ? hint.student_id : nil
        if row && bound && row.connection_id
          GraduateSession.where(graduate_email_connection_id: row.connection_id).order(:id).lock.load
        end
        admission = Limits.admit!(kind: :verify, address_key: address_key, student_id: student_id, ip_key: ip_key, now: now)
        next nil unless admission == :allowed

        initial = row && (row.purpose != 'enroll' || GraduateEmailApproval.find(row.approval_id).replacement_of_connection_id.nil?)
        unless row && bound && initial && Delivery.code_matches?(challenge: row, code: code)
          if row && bound
            attempts = [row.failed_attempts + 1, 5].min
            attributes = {failed_attempts: attempts}
            attributes.merge!(state: 'failed', invalidated_at: now, code_digest: nil) if attempts == 5
            row.update!(attributes)
          end
          Limits.record_failure!(address_key: address_key, student_id: student_id, ip_key: ip_key, now: now)
          next nil
        end

        connection = if row.purpose == 'enroll'
          approval = GraduateEmailApproval.find(row.approval_id)
          created = GraduateEmailConnection.create!(student_id: row.student_id, approved_by_id: approval.approved_by_id,
            normalized_address: approval.normalized_address, verified_at: now)
          GraduateEmailActiveAddress.create!(student_id: row.student_id, connection_id: created.id,
            normalized_address: created.normalized_address)
          approval.update!(consumed_at: now)
          created
        else
          GraduateEmailConnection.find(row.connection_id)
        end
        row.update!(state: 'consumed', consumed_at: now, code_digest: nil)
        token = GraduateSession.issue_email!(connection: connection, generation: control.generation)
        Audit.record!(event: 'authentication', outcome: 'authenticated', student_id: row.student_id,
          connection_id: connection.id, challenge_id: row.id, approval_id: row.approval_id, generation: control.generation)
        Grant.new(student_id: row.student_id, authentication_method: 'email', connection_id: connection.id,
          generation: control.generation, session_token: token)
      end
    rescue GraduateAuthentication::Rejected, ActiveRecord::ActiveRecordError
      nil
    end
  end
end
