# frozen_string_literal: true
module GraduateEmail
  module Revocation
    # Called by Student's after_update, which already owns the student write
    # lock. Never acquire or read control here: that would invert lock order.
    def self.for_student_locked!(student_id:)
      raise GraduateAuthentication::Rejected unless Student.connection.transaction_open?

      now = Time.current
      approvals = GraduateEmailApproval.where(student_id: student_id).order(:id).lock.to_a
      connections = GraduateEmailConnection.where(student_id: student_id).order(:id).lock.to_a
      mappings = GraduateEmailActiveAddress.where(student_id: student_id).order(:id).lock.to_a
      challenges = GraduateEmailChallenge.where(student_id: student_id).order(:id).lock.to_a
      approvals.each { |row| row.update_columns(revoked_at: now, updated_at: now) if row.revoked_at.nil? && row.consumed_at.nil? }
      connections.each { |row| row.update_columns(revoked_at: now, updated_at: now) if row.revoked_at.nil? }
      mappings.each(&:delete)
      challenges.each do |row|
        next if %w[consumed revoked superseded expired failed].include?(row.state)

        row.update_columns(state: 'revoked', invalidated_at: now, code_digest: nil, updated_at: now)
      end
      GraduateSession.revoke_for_student(student_id)
      nil
    end
  end
end
