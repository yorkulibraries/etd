# frozen_string_literal: true
module GraduateEmail
  module Operations
    # Matches the oldest-job alert. A queued notice/real challenge older than
    # this has no progressing worker, including when its job is already gone.
    STALE_QUEUED_AFTER = 60

    class << self
      # Protected process environment only, never a web parameter. Authorization
      # is repeated under Control's lock by set_enabled!, not trusted from here.
      def transition!(enabled:, operator:)
        raise GraduateAuthentication::Rejected unless operator.is_a?(String) && operator.match?(/\A[1-9][0-9]{0,18}\z/)
        raise GraduateAuthentication::Rejected if enabled && !(GraduateEmail.configured? && GraduateEmail.delivery_configured?)

        Control.set_enabled!(enabled: enabled, actor_id: operator.to_i)
      end

      def status
        ActiveRecord::Base.connected_to(role: :writing) do
          GraduateEmailControl.uncached do
            row = GraduateEmailControl.find_by(id: 1)
            raise GraduateAuthentication::Rejected unless row && row.generation.positive? && [true, false].include?(row.enabled)

            otp = Delayed::Job.where(queue: Limits::QUEUE)
            notice = Delayed::Job.where(queue: Limits::NOTICE_QUEUE)
            stale = Time.current - STALE_QUEUED_AFTER
            {control: row.enabled ? 'enabled' : 'disabled', generation: row.generation,
              configuration: GraduateEmail.configured? && GraduateEmail.delivery_configured? ? 'ready' : 'unavailable',
              otp_jobs: otp.count, notice_jobs: notice.count, oldest_seconds: age(otp.or(notice).minimum(:created_at)),
              failed_jobs: otp.or(notice).where.not(failed_at: nil).count,
              oldest_failed_seconds: age(otp.or(notice).minimum(:failed_at)),
              notice_failed: GraduateEmailNotice.where(state: 'failed').count,
              notice_abandoned: GraduateEmailNotice.where(state: 'claimed').where('claimed_at <= ?', 30.seconds.ago).count,
              notice_stale_queued: GraduateEmailNotice.where(state: 'queued').where('created_at <= ?', stale).count,
              otp_stale_queued: GraduateEmailChallenge.where(state: 'queued').where('created_at <= ?', stale).count,
              challenges: GraduateEmailChallenge.count, cooldowns: GraduateEmailCooldown.count,
              limit_events: GraduateEmailLimitEvent.count}
          end
        end
      rescue StandardError
        {control: 'unavailable'}
      end

      private

      def age(time)
        time ? [(Time.current - time).floor, 0].max : 0
      end
    end
  end
end
