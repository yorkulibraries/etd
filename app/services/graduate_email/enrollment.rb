# frozen_string_literal: true
require 'digest'

module GraduateEmail
  module Enrollment
    TOKEN_FORMAT = /\A[A-Za-z0-9_-]{43}\z/

    class << self
      def issue!(student:, actor:, address:, confirmed_address:, identity_verified:, impersonating:, replacement: false)
        normalized = Address.normalize(input: address)
        raise GraduateAuthentication::Rejected unless normalized && normalized == Address.normalize(input: confirmed_address) &&
          identity_verified == true && impersonating == false && [true, false].include?(replacement) && student&.persisted? && actor&.persisted?

        Control.synchronize do |control|
          now = Time.current
          users = User.where(id: [student.id, actor.id]).order(:id).lock.index_by(&:id)
          raise GraduateAuthentication::Rejected unless control.enabled && GraduateEmail.configured? &&
            GraduateAuthentication.active_student?(users[student.id]) && authorized?(users[actor.id])

          pending = GraduateEmailApproval.where(student_id: student.id).order(:id).lock.to_a
          connections = GraduateEmailConnection.where(student_id: student.id).order(:id).lock.to_a
          mappings = GraduateEmailActiveAddress.where('student_id = ? OR normalized_address = ?', student.id, normalized).order(:id).lock.to_a
          raise GraduateAuthentication::Rejected if mappings.any? { |row| row.student_id != student.id }
          current = mappings.find { |row| row.student_id == student.id }
          old = current && connections.find { |row| row.id == current.connection_id }
          if replacement
            raise GraduateAuthentication::Rejected unless old && old.revoked_at.nil? && old.verified_at &&
              current.normalized_address == old.normalized_address
          else
            raise GraduateAuthentication::Rejected if current || connections.any? { |row| row.revoked_at.nil? }
          end
          GraduateEmailChallenge.where(approval_id: pending.map(&:id)).order(:id).lock.load
          pending.each do |approval|
            next unless approval.revoked_at.nil? && approval.consumed_at.nil?
            cancel_locked!(approval, now)
            Audit.record!(event: 'approval', outcome: 'superseded', student_id: student.id,
              actor_id: actor.id, approval_id: approval.id, generation: control.generation)
          end
          token = SecureRandom.urlsafe_base64(32)
          approval = GraduateEmailApproval.create!(student_id: student.id, approved_by_id: actor.id,
            normalized_address: normalized, token_digest: Digest::SHA256.hexdigest(token),
            generation: control.generation, expires_at: now + 48.hours,
            replacement_of_connection_id: replacement ? old.id : nil)
          Audit.record!(event: 'approval', outcome: 'approved', student_id: student.id,
            actor_id: actor.id, approval_id: approval.id, generation: control.generation)
          [approval, token]
        end
      rescue ActiveRecord::ActiveRecordError
        raise GraduateAuthentication::Rejected, 'Email approval unavailable', cause: nil
      end

      def intent!(token:, browser_token:)
        raise GraduateAuthentication::Rejected unless token.is_a?(String) && TOKEN_FORMAT.match?(token)
        Challenges.browser_digest(browser_token: browser_token, purpose: :enroll)
        Control.synchronize do |control|
          now = Time.current
          hint = GraduateEmailApproval.find_by(token_digest: Digest::SHA256.hexdigest(token))
          raise GraduateAuthentication::Rejected unless hint
          users = User.where(id: [hint.student_id, hint.approved_by_id]).order(:id).lock.index_by(&:id)
          approval = GraduateEmailApproval.lock.find_by(id: hint.id)
          raise GraduateAuthentication::Rejected unless control.enabled && GraduateEmail.configured? && approval &&
            approval.token_digest == Digest::SHA256.hexdigest(token) && approval.generation == control.generation &&
            approval.student_id == hint.student_id && approval.approved_by_id == hint.approved_by_id &&
            approval.revoked_at.nil? && approval.consumed_at.nil? && approval.expires_at > now &&
            approval.created_at <= now && approval.created_at > now - 48.hours && approval.expires_at <= approval.created_at + 48.hours &&
            GraduateAuthentication.active_student?(users[approval.student_id]) && authorized?(users[approval.approved_by_id])
          connections = GraduateEmailConnection.where(student_id: approval.student_id).order(:id).lock.to_a
          mappings = GraduateEmailActiveAddress.where('student_id = ? OR normalized_address = ?', approval.student_id, approval.normalized_address).order(:id).lock.to_a
          raise GraduateAuthentication::Rejected if mappings.any? { |row| row.student_id != approval.student_id }
          mapping = mappings.find { |row| row.student_id == approval.student_id }
          if approval.replacement_of_connection_id
            old = connections.find { |row| row.id == approval.replacement_of_connection_id }
            raise GraduateAuthentication::Rejected unless old && old.revoked_at.nil? && old.verified_at && mapping &&
              mapping.connection_id == old.id && mapping.normalized_address == old.normalized_address
          else
            raise GraduateAuthentication::Rejected if mapping
          end
          approval.id
        end
      rescue ActiveRecord::ActiveRecordError
        raise GraduateAuthentication::Rejected, 'Email approval unavailable', cause: nil
      end

      # Caller owns control/users/approval locks. Never touch Google invitations.
      def cancel_locked!(approval, now)
        return unless approval.revoked_at.nil? && approval.consumed_at.nil?

        approval.update!(revoked_at: now)
        GraduateEmailChallenge.where(approval_id: approval.id, state: Challenges::LIVE_STATES).order(:id).lock.each do |row|
          row.update!(state: 'revoked', invalidated_at: now, code_digest: nil)
        end
      end

      def authorized?(actor)
        GraduateAuthentication.staff_authorized?(actor) && !actor.is_a?(Student)
      end
    end
  end
end
