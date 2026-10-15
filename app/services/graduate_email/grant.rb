# frozen_string_literal: true
module GraduateEmail
  class Grant
    attr_reader :student_id, :authentication_method, :connection_id, :generation, :session_token

    def initialize(student_id:, authentication_method:, connection_id:, generation:, session_token:)
      raise GraduateAuthentication::Rejected unless authentication_method == 'email' &&
        [student_id, connection_id, generation].all? { |id| id.is_a?(Integer) && id.positive? } &&
        session_token.is_a?(String) && GraduateSession::TOKEN_FORMAT.match?(session_token)

      @student_id, @connection_id, @generation = student_id, connection_id, generation
      @authentication_method = authentication_method.dup.freeze
      @session_token = session_token.dup.freeze
      freeze
    end

    def inspect
      '#<GraduateEmail::Grant [FILTERED]>'
    end
    alias to_s inspect
  end
end
