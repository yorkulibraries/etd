# frozen_string_literal: true
module GraduateEmail
  module Revocation
    def self.approval!(approval:, actor:, impersonating:)
      raise GraduateAuthentication::Rejected unless impersonating == false && approval&.persisted? && actor&.persisted?

      Control.synchronize do |control|
        hint = GraduateEmailApproval.find_by(id: approval.id)
        raise GraduateAuthentication::Rejected unless hint
        users = User.where(id: [hint.student_id, actor.id]).order(:id).lock.index_by(&:id)
        raise GraduateAuthentication::Rejected unless Enrollment.authorized?(users[actor.id])
        current = GraduateEmailApproval.lock.find_by(id: hint.id)
        raise GraduateAuthentication::Rejected unless current && current.student_id == hint.student_id
        Enrollment.cancel_locked!(current, Time.current)
        Audit.record!(event: 'approval', outcome: 'canceled', student_id: current.student_id,
          actor_id: actor.id, approval_id: current.id, generation: control.generation)
      end
      nil
    rescue ActiveRecord::ActiveRecordError
      raise GraduateAuthentication::Rejected, 'Email approval unavailable', cause: nil
    end

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
