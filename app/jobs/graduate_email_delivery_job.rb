# frozen_string_literal: true
# Custom Delayed Job payload. Serialization contains only an opaque identifier.
class GraduateEmailDeliveryJob
  attr_reader :challenge_public_id

  def initialize(challenge_public_id)
    raise GraduateAuthentication::Rejected unless challenge_public_id.is_a?(String) && challenge_public_id.match?(/\A[0-9a-f]{64}\z/)

    @challenge_public_id = challenge_public_id.dup.freeze
  end

  def perform
    GraduateEmail::Delivery.perform!(challenge_public_id: challenge_public_id)
    nil
  rescue StandardError
    # A raw error must never reach backend last_error or exception notifiers.
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
