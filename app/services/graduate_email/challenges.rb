# frozen_string_literal: true
module GraduateEmail
  module Challenges
    PURPOSES = %i[login enroll].freeze
    LIVE_STATES = %w[queued claimed sending sent].freeze
    TOKEN_FORMAT = /\A[0-9a-f]{64}\z/

    class << self
      # The HTTP caller supplies its signed/encrypted session, never params.
      # Purpose entries are independent and must survive throttled resends.
      def browser_token!(session:, purpose:)
        raise GraduateAuthentication::Rejected unless PURPOSES.include?(purpose)

        name = "graduate_email_#{purpose}_browser_token"
        session[name] = SecureRandom.hex(32) unless token?(session[name])
        session[name]
      end

      def browser_digest(browser_token:, purpose:)
        raise GraduateAuthentication::Rejected unless PURPOSES.include?(purpose) && token?(browser_token)

        Limits.key(domain: "browser:#{purpose}", value: browser_token)
      end

      # Enrollment approval_id is a server-validated enrollment intent, not a
      # posted student/recipient. Task 5 owns invitation-token/intent validation.
      # ip must come from Limits.request_ip(request:), which gates Rails
      # request.remote_ip on the configured trusted immediate proxy peer.
      def request!(purpose:, browser_token:, ip:, address: nil, approval_id: nil)
        previous_id = nil
        Control.synchronize do |control|
          now = Time.current
          raise GraduateAuthentication::Rejected unless GraduateEmail.configured?

          valid_browser = PURPOSES.include?(purpose) && token?(browser_token)
          digest = valid_browser ? browser_digest(browser_token: browser_token, purpose: purpose) :
            Limits.key(domain: 'browser:invalid', value: SecureRandom.hex(32))
          ip_digest = Limits.ip_key(input: ip)
          admission = Limits.send_admission(ip_key: ip_digest, now: now)
          # This bounded browser-only read retains the form's current public ID
          # even when saturation precludes all request/target writes.
          previous_id = existing(digest, purpose, control.generation, now).last&.public_id if valid_browser
          next RequestResult.new(challenge_public_id: previous_id) if admission == :capacity

          target = if admission == :allowed && control.enabled && valid_browser
            eligible_target(purpose, address, approval_id, control, now)
          end
          address_digest = target && Limits.address_key(input: target.normalized_address)
          real = target && Limits.send_allowed?(address_key: address_digest, now: now)
          previous = valid_browser ? existing(digest, purpose, control.generation, now).lock.to_a : []
          previous_id = previous.last&.public_id
          if real
            previous.each { |row| row.update!(state: 'superseded', invalidated_at: now, code_digest: nil) }
          end
          row = GraduateEmailChallenge.create!(public_id: SecureRandom.hex(32),
            purpose: real ? purpose.to_s : 'noop', state: real ? 'queued' : 'noop',
            browser_digest: digest, generation: control.generation, expires_at: now + 5.minutes,
            address_key: real ? address_digest : nil, student_id: real ? target.student_id : nil,
            approval_id: real && purpose == :enroll ? target.id : nil,
            connection_id: real && purpose == :login ? target.id : nil)
          # All subordinate target/challenge locks precede limit reservations.
          reserved = Limits.admit!(kind: :send, ip_key: ip_digest, now: now)
          raise GraduateAuthentication::Rejected unless reserved == admission

          Limits.reserve_send!(address_key: address_digest, now: now) if real
          job = Delayed::Job.enqueue(GraduateEmailDeliveryJob.new(row.public_id), queue: Limits::QUEUE)
          raise GraduateAuthentication::Rejected unless job&.persisted?

          RequestResult.new(challenge_public_id: real ? row.public_id : (previous_id || row.public_id))
        end
      rescue GraduateAuthentication::Rejected, ActiveRecord::ActiveRecordError
        RequestResult.new(challenge_public_id: previous_id)
      end

      private

      def token?(value)
        value.is_a?(String) && TOKEN_FORMAT.match?(value)
      end

      def existing(digest, purpose, generation, now)
        GraduateEmailChallenge.where(browser_digest: digest, purpose: purpose.to_s, generation: generation,
          state: LIVE_STATES, invalidated_at: nil, consumed_at: nil).where('expires_at > ? AND failed_attempts < 5', now).order(:id)
      end

      def eligible_target(purpose, address, approval_id, control, now)
        # Unlocked lookups are hints only. No address key is created for unknown
        # mailboxes. The selected target/student/approver are reread under locks.
        hint = if purpose == :enroll
          GraduateEmailApproval.find_by(id: approval_id) if approval_id.is_a?(Integer) && approval_id.positive?
        else
          normalized = Address.normalize(input: address)
          mapping = GraduateEmailActiveAddress.find_by(normalized_address: normalized) if normalized
          GraduateEmailConnection.find_by(id: mapping.connection_id) if mapping
        end
        return unless hint

        users = User.where(id: [hint.student_id, hint.approved_by_id]).order(:id).lock.index_by(&:id)
        student = users[hint.student_id]
        approver = users[hint.approved_by_id]
        return unless GraduateAuthentication.active_student?(student)

        if purpose == :enroll
          # Pending approvals need a currently authorized approver. A verified
          # connection's approved_by is a historical audit reference only.
          return unless GraduateAuthentication.staff_authorized?(approver) && !approver.is_a?(Student)

          approval = GraduateEmailApproval.where(id: hint.id).lock.first
          return unless same_owner?(approval, hint) && approval.generation == control.generation &&
            approval.revoked_at.nil? && approval.consumed_at.nil? && approval.expires_at > now &&
            approval.created_at <= now && approval.created_at > now - 48.hours &&
            approval.expires_at <= approval.created_at + 48.hours

          # Replacement must still point at the current mapping; initial
          # enrollment cannot silently replace an existing connection.
          connections = GraduateEmailConnection.where(student_id: student.id).order(:id).lock.to_a
          mappings = GraduateEmailActiveAddress.where('student_id = ? OR normalized_address = ?', student.id, approval.normalized_address).order(:id).lock.to_a
          return if mappings.any? { |row| row.student_id != student.id }

          current = mappings.find { |row| row.student_id == student.id }
          if approval.replacement_of_connection_id
            old = connections.find { |row| row.id == approval.replacement_of_connection_id }
            return unless old && old.revoked_at.nil? && current && current.connection_id == old.id && current.normalized_address == old.normalized_address
          else
            return if current
          end
          approval
        else
          connection = GraduateEmailConnection.where(id: hint.id).lock.first
          return unless same_owner?(connection, hint) && connection.revoked_at.nil? && connection.verified_at && connection.normalized_address == Address.normalize(input: address)

          mapping = GraduateEmailActiveAddress.where(student_id: student.id).lock.first
          connection if mapping && mapping.connection_id == connection.id && mapping.normalized_address == connection.normalized_address
        end
      end

      def same_owner?(row, hint)
        row && row.student_id == hint.student_id && row.approved_by_id == hint.approved_by_id &&
          row.normalized_address == hint.normalized_address
      end
    end
  end
end
