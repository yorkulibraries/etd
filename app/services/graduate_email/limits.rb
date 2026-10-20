# frozen_string_literal: true
require 'openssl'
require 'ipaddr'

module GraduateEmail
  module Limits
    QUEUE = 'graduate_email'
    NOTICE_QUEUE = 'graduate_email_notice'
    QUEUE_CAPACITY = 500
    NOTICE_CAPACITY = 50
    FAILURE_RULES = { 'verify_address' => 10, 'verify_student' => 10, 'verify_ip' => 50 }.freeze

    class << self
      # These keys never contain a raw mailbox, student identifier or IP. Invalid
      # IP input shares one bounded bucket rather than choosing arbitrary keys.
      def address_key(input:)
        normalized = Address.normalize(input: input)
        key(domain: 'address', value: normalized) if normalized
      end

      def student_key(student_id:)
        raise GraduateAuthentication::Rejected unless student_id.is_a?(Integer) && student_id.positive?

        key(domain: 'student', value: student_id.to_s)
      end

      def ip_key(input:)
        key(domain: 'ip', value: canonical_ip(input) || 'invalid')
      end

      # Rails 7's RemoteIp assumes an edge has sanitized forwarding headers.
      # Gate their use on the immediate peer before accepting request.remote_ip.
      # Future HTTP callers must use this adapter, never a params/header value.
      def request_ip(request:)
        peer = canonical_ip(request.get_header('REMOTE_ADDR'))
        return unless peer

        proxies = Rails.application.config.action_dispatch.trusted_proxies || ActionDispatch::RemoteIp::TRUSTED_PROXIES
        return peer unless proxies.any? { |proxy| proxy === peer }

        canonical_ip(request.remote_ip.to_s)
      rescue ActionDispatch::RemoteIp::IpSpoofAttackError
        peer
      end

      # Also used for browser bindings, with a separate HMAC domain from keys.
      def key(domain:, value:)
        secret = ENV['GRADUATE_EMAIL_LIMIT_KEY']
        raise GraduateAuthentication::Rejected unless GraduateEmail.configured? && secret.is_a?(String) && secret.bytesize >= 32

        data = ['graduate-email-v1', domain, value].map { |part| "#{part.bytesize}:#{part}" }.join
        OpenSSL::HMAC.hexdigest('SHA256', secret, data)
      end

      # Read-only preflight allows callers to check global/IP admission before
      # looking up any target while deferring event writes until after row locks.
      def send_admission(ip_key:, now:)
        owned!
        return :capacity if capacity?(kind: :send, now: now)
        return :limited if count('request_ip', ip_key, now, 1.hour) >= 20

        :allowed
      end

      # Read-only global/IP preflight before any target lookup. Event writes
      # remain after target/challenge/session locks in the caller transaction.
      def verify_admission(ip_key:, now:)
        owned!
        return :capacity if capacity?(kind: :verify, now: now)
        cooling?('verify_ip', ip_key, now) ? :limited : :allowed
      end

      def admit!(kind:, address_key: nil, student_id: nil, ip_key:, now:)
        owned!
        raise GraduateAuthentication::Rejected unless %i[send verify].include?(kind) && digest?(ip_key)
        return :capacity if capacity?(kind: kind, now: now)

        event!("admission_#{kind}", global_key, now)
        if kind == :send
          return :limited if count('request_ip', ip_key, now, 1.hour) >= 20

          event!('request_ip', ip_key, now)
          :allowed
        else
          keys = failure_keys(address_key, student_id, ip_key)
          keys.each { |name, digest| expire_cooldown!(name, digest, now) }
          keys.any? { |name, digest| cooling?(name, digest, now) } ? :limited : :allowed
        end
      end

      def send_allowed?(address_key:, now:)
        owned!
        return false unless digest?(address_key)

        rows = window('send_address', address_key, now, 1.hour)
        rows.count < 5 && !rows.where('occurred_at > ?', now - 60.seconds).exists?
      end

      # Call only for an accepted real challenge, in its insertion transaction.
      def reserve_send!(address_key:, now:)
        raise GraduateAuthentication::Rejected unless send_allowed?(address_key: address_key, now: now)

        event!('send_address', address_key, now)
        nil
      end

      # Future redemption must call admit! once for every verification, including
      # malformed attempts, then record a failure only for an allowed attempt.
      # Address/student come exclusively from its server-bound challenge.
      def record_failure!(address_key:, student_id:, ip_key:, now:)
        owned!
        keys = failure_keys(address_key, student_id, ip_key)
        keys.each { |name, digest| expire_cooldown!(name, digest, now) }
        return nil if keys.any? { |name, digest| cooling?(name, digest, now) }

        keys.each do |name, digest|
          event!(name, digest, now)
          if count(name, digest, now, 15.minutes) >= FAILURE_RULES.fetch(name)
            GraduateEmailCooldown.create!(kind: name, key_digest: digest, blocked_until: now + 15.minutes)
          end
        end
        nil
      end

      private

      def canonical_ip(input)
        return unless input.is_a?(String) && input.bytesize <= 45 && input.match?(/\A[0-9a-fA-F:.]+\z/)

        IPAddr.new(input).native.to_s
      rescue IPAddr::InvalidAddressError
        nil
      end

      def owned!
        Control.locked_state!
      end

      def digest?(value)
        value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/)
      end

      def global_key
        key(domain: 'global', value: 'admission')
      end

      def capacity?(kind:, now:)
        maximum = kind == :send ? 120 : 300
        count("admission_#{kind}", global_key, now, 1.minute) >= maximum ||
          (kind == :send && Delayed::Job.where(queue: QUEUE).count >= QUEUE_CAPACITY)
      end

      def window(kind, digest, now, duration)
        GraduateEmailLimitEvent.where(kind: kind, key_digest: digest).where('occurred_at > ? AND occurred_at <= ?', now - duration, now)
      end

      def count(kind, digest, now, duration)
        window(kind, digest, now, duration).count
      end

      def event!(kind, digest, now)
        GraduateEmailLimitEvent.create!(kind: kind, key_digest: digest, occurred_at: now)
      end

      def failure_keys(address, student, ip)
        raise GraduateAuthentication::Rejected unless digest?(ip) && (address.nil? || digest?(address))

        keys = []
        keys << ['verify_address', address] if address
        keys << ['verify_student', student_key(student_id: student)] if student
        keys << ['verify_ip', ip]
        keys
      end

      def cooling?(kind, digest, now)
        GraduateEmailCooldown.where(kind: kind, key_digest: digest).where('blocked_until > ?', now).exists?
      end

      def expire_cooldown!(kind, digest, now)
        row = GraduateEmailCooldown.find_by(kind: kind, key_digest: digest)
        return unless row && row.blocked_until <= now

        GraduateEmailLimitEvent.where(kind: kind, key_digest: digest).delete_all
        row.delete
      end
    end
  end
end
