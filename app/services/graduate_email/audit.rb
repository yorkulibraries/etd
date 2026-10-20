# frozen_string_literal: true
module GraduateEmail
  module Audit
    # Policy events only. Never persist request input, exception text or secrets.
    EVENTS = %w[control enrollment authentication approval connection replacement revocation].freeze
    OUTCOMES = %w[enabled disabled approved consumed authenticated canceled superseded revoked replaced].freeze

    def self.record!(event:, outcome:, generation:, student_id: nil, actor_id: nil, connection_id: nil, approval_id: nil, challenge_id: nil)
      raise GraduateAuthentication::Rejected unless EVENTS.include?(event) && OUTCOMES.include?(outcome) &&
        generation.is_a?(Integer) && generation.positive?

      GraduateEmailAuditEvent.create!(event: event, outcome: outcome, generation: generation,
        student_id: student_id, actor_id: actor_id, connection_id: connection_id, approval_id: approval_id, challenge_id: challenge_id)
    end
  end
end
