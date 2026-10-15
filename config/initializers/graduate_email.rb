# frozen_string_literal: true

# Configuration is deliberately independent of Google and never queries feature
# tables during boot (including a pre-migration or rolled-back deployment).
module GraduateEmail
  class << self
    attr_reader :base_url

    def configure!
      @base_url = GraduateAuthentication.send(:validated_base_url, ENV['GRADUATE_EMAIL_BASE_URL'])
      code_key = ENV['GRADUATE_EMAIL_CODE_KEY']
      limit_key = ENV['GRADUATE_EMAIL_LIMIT_KEY']
      @configured = @base_url.present? && [code_key, limit_key].all? { |key| key.is_a?(String) && key.bytesize >= 32 } &&
                    code_key != limit_key && [code_key, limit_key].none? { |key| key == Rails.application.secret_key_base }
      nil
    end

    def configured?
      @configured == true
    end
  end
end

GraduateEmail.configure!
