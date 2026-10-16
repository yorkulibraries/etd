# frozen_string_literal: true
# Custom Delayed Job payload. Serialization contains only an opaque identifier.
class GraduateEmailDeliveryJob
  attr_reader :challenge_public_id

  def initialize(challenge_public_id)
    raise GraduateAuthentication::Rejected unless challenge_public_id.is_a?(String) && challenge_public_id.match?(/\A[0-9a-f]{64}\z/)

    @challenge_public_id = challenge_public_id.dup.freeze
  end

  def perform
    # Task 4 replaces this safe branch with Delivery.perform!. There is no code
    # generation, unavailable future constant, mailer, approval or session work.
    failed_id = nil
    GraduateEmail::Control.synchronize do
      row = GraduateEmailChallenge.find_by(public_id: challenge_public_id)
      next unless row && row.purpose != 'noop' && row.state == 'queued'

      Student.where(id: row.student_id).order(:id).lock.load
      row = GraduateEmailChallenge.where(id: row.id).lock.first
      next unless row && row.state == 'queued'

      row.update!(state: 'failed', code_digest: nil, invalidated_at: Time.current)
      failed_id = row.id
    end
    Rails.logger.warn("graduate_email delivery_not_ready challenge_id=#{failed_id}") if failed_id
    nil
  rescue StandardError
    # Never allow backend last_error/notifiers to receive an original exception
    # (including SQL/SMTP payloads). A later duplicate remains safe as well.
    Rails.logger.warn('graduate_email delivery_not_ready')
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
    '#<GraduateEmailDeliveryJob [FILTERED]>'
  end
  alias to_s inspect
end
