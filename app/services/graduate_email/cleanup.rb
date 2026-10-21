# frozen_string_literal: true
module GraduateEmail
  module Cleanup
    BATCH_SIZE = 500
    MAX_BATCHES = 200 # 100,000/category: exceeds 93,600 maximum events/hour
    # (120 sends/min * 3 + 300 verifies/min * 4) * 60, while each
    # transaction remains <=500 rows and each invocation is finite.

    class << self
      def call
        now = Time.current
        counts = {jobs: 0, challenges: 0, sessions: 0, events: 0, cooldowns: 0, notices: 0}
        # Separate fresh short control transactions serialize with email writes;
        # never require enabled/configured state and never recreate missing state.
        # Jobs first, then target deletion; SET NULL retains policy audit history.
        counts[:jobs] = prune_jobs(now)
        counts[:challenges] = prune { GraduateEmailChallenge.where('expires_at <= ?', now - 24.hours) }
        counts[:sessions] = prune { GraduateSession.where('expires_at <= ?', now - 24.hours) }
        counts[:events] = prune do
          GraduateEmailLimitEvent.where('occurred_at <= ?', now - 2.hours)
            .where('NOT EXISTS (SELECT 1 FROM graduate_email_cooldowns c WHERE c.kind = graduate_email_limit_events.kind AND c.key_digest = graduate_email_limit_events.key_digest AND c.blocked_until > ?)', now - 2.hours)
        end
        counts[:cooldowns] = prune { GraduateEmailCooldown.where('blocked_until <= ?', now - 2.hours) }
        counts[:notices] = prune do
          GraduateEmailNotice.where(state: %w[sent failed]).where('updated_at <= ?', now - 24.hours)
            .or(GraduateEmailNotice.where(state: 'claimed').where('claimed_at <= ?', now - 24.hours))
        end
        counts
      end

      private

      def prune
        total = 0
        MAX_BATCHES.times do
          removed = Control.synchronize do
            relation = yield
            ids = relation.order(:id).limit(BATCH_SIZE).pluck(:id)
            ids.empty? ? 0 : relation.where(id: ids).delete_all
          end
          total += removed
          break if removed < BATCH_SIZE
        end
        total
      end

      def prune_jobs(now)
        total = 0
        cursor = 0
        MAX_BATCHES.times do
          scanned, removed, cursor = Control.synchronize do
            jobs = Delayed::Job.where(queue: [Limits::QUEUE, Limits::NOTICE_QUEUE])
              .where('id > ? AND created_at <= ?', cursor, now - 24.hours)
              .where('locked_at IS NULL OR locked_at <= ?', now - 30.seconds).order(:id).limit(BATCH_SIZE).lock.to_a
            ids = jobs.select { |job| disposable_job?(job, now) }.map(&:id)
            deleted = ids.empty? ? 0 : Delayed::Job.where(id: ids).delete_all
            [jobs.size, deleted, jobs.last&.id || cursor]
          end
          total += removed
          break if scanned < BATCH_SIZE
        end
        total
      end

      def disposable_job?(job, now)
        # Deserialize only private queues. Unknown payload classes are preserved.
        case payload = job.payload_object
        when GraduateEmailDeliveryJob
          row = GraduateEmailChallenge.find_by(public_id: payload.challenge_public_id)
          row.nil? || row.expires_at <= now - 24.hours
        when GraduateEmailNoticeJob
          row = GraduateEmailNotice.find_by(id: payload.notice_id)
          row.nil? || (%w[sent failed].include?(row.state) && row.updated_at <= now - 24.hours) ||
            (row.state == 'claimed' && row.claimed_at && row.claimed_at <= now - 24.hours)
        else
          false
        end
      rescue StandardError
        false
      end
    end
  end
end
