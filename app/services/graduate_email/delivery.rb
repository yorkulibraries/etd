# frozen_string_literal: true
require 'openssl'
require 'securerandom'
require 'timeout'

module GraduateEmail
  module Delivery
    DELIVERY_DEADLINE = 10
    FORMAT = /\A[0-9a-f]{64}\z/
    CODE_FORMAT = /\A[0-9]{6}\z/

    # Never serialized, persisted or attached to an event/exception. Copying
    # retains frozen independent strings; inspection never reveals the secret.
    class Claim
      attr_reader :public_id, :generation, :claimed_at, :digest, :code
      def initialize(row:, code:)
        @public_id = row.public_id.dup.freeze
        @generation = row.generation
        @claimed_at = row.claimed_at.dup.freeze
        @digest = row.code_digest.dup.freeze
        @code = code.dup.freeze
        freeze
      end

      def initialize_copy(other)
        super
        freeze
      end

      def marshal_dump
        raise TypeError, 'Memory-only graduate claim'
      end

      def as_json(*)
        '[FILTERED]'
      end

      def inspect
        '#<GraduateEmail::Delivery::Claim [FILTERED]>'
      end
      alias to_s inspect
    end

    class Envelope
      attr_reader :recipient, :expires_at
      def initialize(recipient:, expires_at:)
        @recipient = recipient.dup.freeze
        @expires_at = expires_at.dup.freeze
        freeze
      end

      def inspect
        '#<GraduateEmail::Delivery::Envelope [FILTERED]>'
      end
      alias to_s inspect
    end

    class << self
      def perform!(challenge_public_id:)
        claim = claim!(challenge_public_id: challenge_public_id)
        return unless claim

        envelope = authorize_send!(claim: claim)
        return unless envelope

        # The only external effect. Never wrap this in a DB transaction. The
        # dedicated builder bypasses ActionMailer process/deliver instrumentation.
        begin
          raise GraduateAuthentication::Rejected unless GraduateEmail.delivery_configured?
          Timeout.timeout(DELIVERY_DEADLINE) do
            GraduateAuthenticationMailer.code(recipient: envelope.recipient, code: claim.code,
              expires_at: envelope.expires_at).deliver!
          end
        rescue StandardError
          fail_after_error(claim)
          diagnostic(:delivery_failed)
          return nil
        end
        finalize!(claim: claim, outcome: :sent)
        nil
      rescue StandardError
        # Includes database/render/config failures. The backend and its exception
        # notifier never receive the original error or its cause/backtrace.
        diagnostic(:delivery_unavailable)
        nil
      end

      def claim!(challenge_public_id:)
        return unless opaque_id?(challenge_public_id) && GraduateEmail.delivery_configured?

        Control.synchronize do
          now = instant
          row, _target, valid = locked_context(challenge_public_id, %w[queued], now)
          next unless row && row.state == 'queued'
          unless valid
            invalidate!(row, now)
            next
          end
          code = format('%06d', SecureRandom.random_number(1_000_000))
          row.update!(state: 'claimed', claimed_at: now, code_digest: code_digest(challenge: row, code: code))
          Claim.new(row: row, code: code)
        end
      end

      def authorize_send!(claim:)
        return unless claim.is_a?(Claim)

        Control.synchronize do
          now = instant
          row, target, valid = locked_context(claim.public_id, %w[claimed], now)
          next unless same_claim?(row, claim, 'claimed')
          unless valid && GraduateEmail.delivery_configured?
            invalidate!(row, now)
            next
          end
          row.update!(state: 'sending', send_authorized_at: now)
          Envelope.new(recipient: target.normalized_address, expires_at: row.expires_at)
        end
      end

      def finalize!(claim:, outcome:)
        raise GraduateAuthentication::Rejected unless claim.is_a?(Claim) && %i[sent failed].include?(outcome)

        Control.synchronize do
          now = instant
          row, _target, valid = locked_context(claim.public_id, %w[sending], now)
          next unless valid && same_claim?(row, claim, 'sending')

          if outcome == :sent
            row.update!(state: 'sent', sent_at: now)
          else
            invalidate!(row, now)
          end
        end
        nil
      end

      # Task 5 must call inside its OWN fresh Control.synchronize transaction,
      # before consuming/issuing. Locks are retained until that caller commits.
      # Return value is internal only, never a public result or controller body.
      def eligible_challenge_locked!(challenge_public_id:, states:, now:)
        raise GraduateAuthentication::Rejected unless states.is_a?(Array) && (states - %w[queued claimed sending sent]).empty?

        row, _target, valid = locked_context(challenge_public_id, states, now)
        valid ? row : nil
      end

      # Context-only digest comparison, NOT authorization. Pair with the above
      # eligibility API, browser binding, attempt/budget checks and atomic consume.
      def code_matches?(challenge:, code:)
        return false unless code.is_a?(String) && CODE_FORMAT.match?(code) &&
          challenge.code_digest.is_a?(String) && FORMAT.match?(challenge.code_digest)

        expected = code_digest(challenge: challenge, code: code)
        expected && ActiveSupport::SecurityUtils.fixed_length_secure_compare(expected, challenge.code_digest)
      rescue GraduateAuthentication::Rejected
        false
      end

      def code_digest(challenge:, code:)
        raise GraduateAuthentication::Rejected unless GraduateEmail.configured? && code.is_a?(String) && CODE_FORMAT.match?(code)

        target = case challenge.purpose
        when 'enroll' then challenge.approval_id
        when 'login' then challenge.connection_id
        end
        raise GraduateAuthentication::Rejected unless target.is_a?(Integer) && target.positive?

        fields = ['graduate-email-code-v1', challenge.purpose, challenge.public_id, challenge.browser_digest,
          target.to_s, challenge.generation.to_s, code]
        OpenSSL::HMAC.hexdigest('SHA256', GraduateEmail.code_key, fields.map { |value| "#{value.bytesize}:#{value}" }.join)
      end

      private

      def instant
        now = Time.current
        now.change(usec: now.usec)
      end

      def opaque_id?(value)
        value.is_a?(String) && FORMAT.match?(value)
      end

      def same_claim?(row, claim, state)
        row && row.state == state && row.public_id == claim.public_id && row.generation == claim.generation &&
          row.claimed_at == claim.claimed_at && row.code_digest == claim.digest &&
          row.invalidated_at.nil? && row.consumed_at.nil?
      end

      def invalidate!(row, now)
        return unless %w[queued claimed sending].include?(row.state)

        row.update!(state: 'failed', code_digest: nil, invalidated_at: now)
      end

      def fail_after_error(claim)
        2.times do
          begin
            finalize!(claim: claim, outcome: :failed)
            return
          rescue StandardError
            # A new Control transaction is attempted once. Never retry SMTP.
          end
        end
      end

      def diagnostic(outcome)
        # Fixed enums only and always after all product transactions ended.
        Rails.logger.warn("graduate_email #{outcome}") if ActiveRecord::Base.connection.open_transactions.zero?
      rescue StandardError
        nil
      end

      def locked_context(public_id, states, now)
        control = Control.locked_state!
        return [nil, nil, false] unless opaque_id?(public_id)

        # Hints never authorize. User locks precede every subordinate lock; read
        # and compare authoritative challenge and target again after those locks.
        hint = GraduateEmailChallenge.find_by(public_id: public_id)
        return [hint, nil, false] unless hint && %w[enroll login].include?(hint.purpose)

        target_hint = hint.purpose == 'enroll' ? GraduateEmailApproval.find_by(id: hint.approval_id) : GraduateEmailConnection.find_by(id: hint.connection_id)
        users = User.where(id: [hint.student_id, target_hint&.approved_by_id]).order(:id).lock.index_by(&:id)
        approvals = GraduateEmailApproval.where(student_id: hint.student_id).order(:id).lock.to_a if hint.purpose == 'enroll'
        connections = GraduateEmailConnection.where(student_id: hint.student_id).order(:id).lock.to_a
        mappings = GraduateEmailActiveAddress.where(student_id: hint.student_id)
        if hint.purpose == 'enroll'
          # Subquery keeps the approved mailbox out of SQL bind notifications.
          mappings = mappings.or(GraduateEmailActiveAddress.where(normalized_address:
            GraduateEmailApproval.where(id: hint.approval_id).select(:normalized_address)))
        end
        mappings = mappings.order(:id).lock.to_a
        row = GraduateEmailChallenge.where(student_id: hint.student_id).order(:id).lock.to_a.find { |item| item.id == hint.id }
        target = hint.purpose == 'enroll' ? approvals.find { |item| item.id == hint.approval_id } : connections.find { |item| item.id == hint.connection_id }
        valid = row && target && target_hint && row.student_id == hint.student_id && row.purpose == hint.purpose &&
          row.approval_id == hint.approval_id && row.connection_id == hint.connection_id &&
          target.student_id == row.student_id && target.approved_by_id == target_hint.approved_by_id &&
          control.enabled && GraduateEmail.configured? && row.generation == control.generation &&
          states.include?(row.state) &&
          (!%w[claimed sending sent].include?(row.state) || (opaque_id?(row.code_digest) && row.claimed_at)) &&
          (!%w[sending sent].include?(row.state) || row.send_authorized_at) && row.invalidated_at.nil? && row.consumed_at.nil? && row.failed_attempts < 5 &&
          row.expires_at > now && row.created_at <= now && row.expires_at <= row.created_at + 5.minutes &&
          opaque_id?(row.browser_digest) &&
          GraduateAuthentication.active_student?(users[row.student_id]) &&
          GraduateAuthentication.staff_authorized?(users[target.approved_by_id]) && !users[target.approved_by_id].is_a?(Student) &&
          Address.normalize(input: target.normalized_address) == target.normalized_address &&
          row.address_key == Limits.address_key(input: target.normalized_address)
        if valid
          mapping = mappings.find { |item| item.student_id == row.student_id }
          if row.purpose == 'enroll'
            old = connections.find { |item| item.id == target.replacement_of_connection_id }
            valid = row.connection_id.nil? && target.generation == control.generation && target.revoked_at.nil? &&
              target.consumed_at.nil? && target.created_at <= now && target.created_at > now - 48.hours &&
              target.expires_at > now && target.expires_at <= target.created_at + 48.hours &&
              mappings.none? { |item| item.student_id != row.student_id } &&
              (target.replacement_of_connection_id ? old && old.revoked_at.nil? && mapping &&
                mapping.connection_id == old.id && mapping.normalized_address == old.normalized_address : mapping.nil?)
          else
            valid = row.approval_id.nil? && target.revoked_at.nil? && target.verified_at && mapping &&
              mapping.connection_id == target.id && mapping.normalized_address == target.normalized_address
          end
        end
        # Accepted resends mark the old row superseded under this same control
        # lock. Never infer invalidation from another browser's newer challenge.
        [row, target, !!valid]
      end
    end
  end
end
