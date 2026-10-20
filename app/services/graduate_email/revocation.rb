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

    def self.connection!(connection:, actor:, impersonating:)
      raise GraduateAuthentication::Rejected unless impersonating == false && connection&.persisted? && actor&.persisted?

      Control.synchronize do |control|
        hint = GraduateEmailConnection.find_by(id: connection.id)
        raise GraduateAuthentication::Rejected unless hint && hint.student_id == connection.student_id
        users = User.where(id: [hint.student_id, actor.id]).order(:id).lock.index_by(&:id)
        student = users[hint.student_id]
        raise GraduateAuthentication::Rejected unless Enrollment.authorized?(users[actor.id]) &&
          student.is_a?(Student) && student.role == User::STUDENT
        approvals = GraduateEmailApproval.where(student_id: student.id).order(:id).lock.to_a
        connections = GraduateEmailConnection.where(student_id: student.id).order(:id).lock.to_a
        mappings = GraduateEmailActiveAddress.where(student_id: student.id).order(:id).lock.to_a
        current = connections.find { |row| row.id == hint.id }
        raise GraduateAuthentication::Rejected unless current && current.student_id == hint.student_id
        next if current.revoked_at
        mapping = mappings.find { |row| row.connection_id == current.id }
        raise GraduateAuthentication::Rejected unless mapping && mapping.normalized_address == current.normalized_address
        challenges = GraduateEmailChallenge.where(student_id: student.id).order(:id).lock.to_a
        GraduateSession.where(graduate_email_connection_id: connections.map(&:id)).order(:id).lock.load
        now = Time.current
        approvals.each { |row| row.update!(revoked_at: now) if row.revoked_at.nil? && row.consumed_at.nil? }
        challenges.each { |row| revoke_challenge_locked!(row, now) }
        # Revoke all historical email sessions too. Google IDs never selected.
        GraduateSession.where(graduate_email_connection_id: connections.map(&:id), revoked_at: nil).update_all(revoked_at: now)
        current.update!(revoked_at: now)
        mapping.delete
        Audit.record!(event: 'revocation', outcome: 'revoked', student_id: student.id,
          actor_id: actor.id, connection_id: current.id, generation: control.generation)
      end
      nil
    rescue ActiveRecord::ActiveRecordError
      raise GraduateAuthentication::Rejected, 'Email connection unavailable', cause: nil
    end

    # Internal replacement primitive; caller already owns ordered locks through
    # sessions and admission. No control/student locks may be acquired here.
    def self.replace_locked!(connection_id:, student_id:, now:, except_challenge_id:)
      Control.locked_state!
      connection = GraduateEmailConnection.find(connection_id)
      mapping = GraduateEmailActiveAddress.find_by(student_id: student_id)
      raise GraduateAuthentication::Rejected unless connection.student_id == student_id && connection.revoked_at.nil? &&
        mapping && mapping.connection_id == connection.id && mapping.normalized_address == connection.normalized_address
      connection.update!(revoked_at: now)
      mapping.delete
      GraduateEmailChallenge.where(student_id: student_id).order(:id).each do |row|
        next if row.id == except_challenge_id
        revoke_challenge_locked!(row, now)
      end
      GraduateSession.where(graduate_email_connection_id: connection_id, revoked_at: nil).update_all(revoked_at: now)
    end

    def self.revoke_challenge_locked!(row, now)
      return unless Challenges::LIVE_STATES.include?(row.state)
      row.update!(state: 'revoked', invalidated_at: now, code_digest: nil)
    end
    private_class_method :revoke_challenge_locked!

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
