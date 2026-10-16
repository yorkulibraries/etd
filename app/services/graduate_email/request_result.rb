# frozen_string_literal: true
module GraduateEmail
  class RequestResult
    MESSAGE = 'If this address is enabled for graduate sign-in, we’ll send a code.'.freeze
    attr_reader :challenge_public_id, :message

    def initialize(challenge_public_id: nil)
      raise GraduateAuthentication::Rejected unless challenge_public_id.nil? ||
        (challenge_public_id.is_a?(String) && challenge_public_id.match?(/\A[0-9a-f]{64}\z/))

      @challenge_public_id = challenge_public_id&.dup&.freeze
      @message = MESSAGE
      freeze
    end

    def inspect
      '#<GraduateEmail::RequestResult [FILTERED]>'
    end
    alias to_s inspect
  end
end
