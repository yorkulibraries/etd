# frozen_string_literal: true
require 'timeout'
class GraduateEmailNoticeJob
  QUEUE = 'graduate_email_notice'
  QUEUE_CAPACITY = 50 # Task 6 producer MUST enforce this retained-row reserve.
  attr_reader :notice_id

  def initialize(notice_id)
    raise GraduateAuthentication::Rejected unless notice_id.is_a?(Integer) && notice_id.positive?

    @notice_id = notice_id
  end

  def perform
    return unless GraduateEmail.delivery_configured?

    # Write first for SQLite too. Notice is an immutable outbox reference; it
    # does not need the feature-control lock and must survive feature disable.
    claim = GraduateEmailNotice.transaction do
      affected = GraduateEmailNotice.where(id: notice_id, state: 'queued', claimed_at: nil)
        .update_all(state: 'claimed', claimed_at: Time.current)
      next unless affected == 1

      row = GraduateEmailNotice.find(notice_id)
      [row.claimed_at, GraduateEmailConnection.find(row.old_connection_id).freeze]
    end
    return unless claim

    begin
      Timeout.timeout(GraduateEmail::Delivery::DELIVERY_DEADLINE) do
        GraduateAuthenticationMailer.access_changed(old_connection: claim[1]).deliver!
      end
      outcome = 'sent'
    rescue StandardError
      outcome = 'failed'
    end
    # Conditional finalize never changes access/mapping or retries a claim.
    GraduateEmailNotice.transaction do
      attributes = {state: outcome, updated_at: Time.current}
      attributes[:sent_at] = Time.current if outcome == 'sent'
      GraduateEmailNotice.where(id: notice_id, state: 'claimed', claimed_at: claim[0], old_connection_id: claim[1].id).update_all(attributes)
    end
    nil
  rescue StandardError
    nil
  end

  def max_attempts
    1
  end

  def max_run_time
    30
  end

  def destroy_failed_jobs?
    true
  end

  def inspect
    '#<GraduateEmailNoticeJob [FILTERED]>'
  end
  alias to_s inspect
end
