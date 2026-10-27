# frozen_string_literal: true
require 'digest'

module GraduateEmail
  module Enrollment
    TOKEN_FORMAT = /\A[A-Za-z0-9_-]{43}\z/
    REASONS = %i[unsupported mismatch active_elsewhere pending_elsewhere state_changed unavailable].freeze

    # Staff-only refusal reason. Still a Rejected, so every existing boundary
    # treats it the same; only the staff controller reads the fixed enum.
    class Refused < GraduateAuthentication::Rejected
      attr_reader :reason, :other_student_id

      def initialize(reason, other_student_id: nil)
        @reason = REASONS.include?(reason) ? reason : :unavailable
        @other_student_id = other_student_id
        super('Email approval refused')
      end
    end

    Review = Struct.new(:reason, :address, :other_student_id)

    class << self
      def issue!(student:, actor:, address:, confirmed_address:, identity_verified:, impersonating:, replacement: false)
        normalized = Address.normalize(input: address)
        raise Refused.new(:unsupported) unless normalized
        raise Refused.new(:mismatch) unless normalized == Address.normalize(input: confirmed_address)
        raise GraduateAuthentication::Rejected unless identity_verified == true && impersonating == false &&
          [true, false].include?(replacement) && student&.persisted? && actor&.persisted?

        Control.synchronize do |control|
          now = Time.current
          users = User.where(id: [student.id, actor.id]).order(:id).lock.index_by(&:id)
          raise Refused.new(:unavailable) unless control.enabled && GraduateEmail.configured? &&
            GraduateAuthentication.active_student?(users[student.id]) && authorized?(users[actor.id])

          pending = GraduateEmailApproval.where(student_id: student.id).order(:id).lock.to_a
          competing = competing_locked(student_id: student.id, address: normalized, generation: control.generation, now: now)
          connections = GraduateEmailConnection.where(student_id: student.id).order(:id).lock.to_a
          mappings = GraduateEmailActiveAddress.where('student_id = ? OR normalized_address = ?', student.id, normalized).order(:id).lock.to_a
          other = mappings.find { |row| row.student_id != student.id }
          raise Refused.new(:active_elsewhere, other_student_id: other.student_id) if other
          raise Refused.new(:pending_elsewhere, other_student_id: competing.first.student_id) if competing.any?
          current = mappings.find { |row| row.student_id == student.id }
          old = current && connections.find { |row| row.id == current.connection_id }
          if replacement
            raise Refused.new(:state_changed) unless old && old.revoked_at.nil? && old.verified_at &&
              current.normalized_address == old.normalized_address
          else
            raise Refused.new(:state_changed) if current || connections.any? { |row| row.revoked_at.nil? }
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

      # Staff preview before issuing: unlocked reads only, never a write or a
      # control lock. issue! repeats every check under locks and is authoritative.
      def review(student:, actor:, address:, confirmed_address:, replacement:)
        normalized = Address.normalize(input: address)
        return Review.new(:unsupported, nil, nil) unless normalized
        return Review.new(:mismatch, nil, nil) unless normalized == Address.normalize(input: confirmed_address)
        return Review.new(:unavailable, nil, nil) unless [true, false].include?(replacement) && Control.enabled? &&
          GraduateAuthentication.active_student?(student) && authorized?(actor)

        control = GraduateEmailControl.find_by(id: 1)
        conflict = conflict_for(student_id: student.id, address: normalized, generation: control.generation, now: Time.current)
        return Review.new(conflict.first, normalized, conflict.last) if conflict

        current = GraduateEmailActiveAddress.find_by(student_id: student.id)
        connected = GraduateEmailConnection.where(student_id: student.id, revoked_at: nil).exists?
        valid = replacement ? current && connected : !current && !connected
        Review.new(valid ? nil : :state_changed, normalized, nil)
      end

      # Staff page only: which of this student's pending approvals are blocked
      # by another student's active or reserving claim. Unlocked, read-only.
      def blocked_approval_ids(approvals)
        control = GraduateEmailControl.find_by(id: 1)
        return [] unless control

        now = Time.current
        approvals.select do |approval|
          reserving?(approval, generation: control.generation, now: now) &&
            conflict_for(student_id: approval.student_id, address: approval.normalized_address, generation: control.generation, now: now)
        end.map(&:id)
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
          raise GraduateAuthentication::Rejected if approval && competing_locked(student_id: approval.student_id,
            address: approval.normalized_address, generation: control.generation, now: now).any?
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

      # A pending approval reserves its address until it can never become usable
      # again: canceled, superseded, consumed, expired or from an old generation.
      # Approver or student status is not a release because it can be restored,
      # which would revive a competing claim.
      def reserving?(approval, generation:, now:)
        approval.revoked_at.nil? && approval.consumed_at.nil? && approval.generation == generation &&
          approval.expires_at > now && approval.created_at > now - 48.hours
      end

      # Caller owns control and the student's user lock, at the approvals stage.
      # Only control holders create approvals, so the unlocked candidate read is
      # complete; locking by primary key avoids locking unrelated rows. address_scope
      # may be a subquery so the mailbox stays out of SQL bind notifications.
      def competing_locked(student_id:, address:, generation:, now:, address_scope: address)
        Control.locked_state!
        ids = GraduateEmailApproval.where(normalized_address: address_scope).where.not(student_id: student_id).pluck(:id)
        return [] if ids.empty?

        GraduateEmailApproval.where(id: ids).order(:id).lock.to_a.select do |row|
          row.student_id != student_id && row.normalized_address == address && reserving?(row, generation: generation, now: now)
        end
      end

      private

      def conflict_for(student_id:, address:, generation:, now:)
        active = GraduateEmailActiveAddress.where(normalized_address: address).where.not(student_id: student_id).first
        return [:active_elsewhere, active.student_id] if active

        pending = GraduateEmailApproval.where(normalized_address: address).where.not(student_id: student_id).order(:id)
          .find { |row| reserving?(row, generation: generation, now: now) }
        [:pending_elsewhere, pending.student_id] if pending
      end
    end
  end
end
