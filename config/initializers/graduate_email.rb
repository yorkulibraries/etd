# frozen_string_literal: true

require 'openssl'
require 'uri'

# Configuration is deliberately independent of Google and never queries feature
# tables during boot (including a pre-migration or rolled-back deployment).
module GraduateEmail
  class << self
    attr_reader :base_url, :code_key, :from_address, :smtp_settings

    def configure!
      @base_url = GraduateAuthentication.send(:validated_base_url, ENV['GRADUATE_EMAIL_BASE_URL'])
      code_key = ENV['GRADUATE_EMAIL_CODE_KEY']
      limit_key = ENV['GRADUATE_EMAIL_LIMIT_KEY']
      @configured = @base_url.present? && [code_key, limit_key].all? { |key| key.is_a?(String) && key.bytesize >= 32 } &&
                    code_key != limit_key && [code_key, limit_key].none? { |key| key == Rails.application.secret_key_base }
      @code_key = @configured ? code_key.dup.freeze : nil
      configure_delivery!
      nil
    end

    def delivery_configured?
      @delivery_configured == true
    end

    def configure_delivery!
      # No table reads or inherited ActionMailer defaults. Missing/invalid
      # configuration disables this transport only, including during rollback.
      sender = ENV['GRADUATE_EMAIL_FROM']
      @from_address = GraduateEmail::Address.normalize(input: sender)
      host = ENV['GRADUATE_EMAIL_SMTP_ADDRESS']
      port = ENV['GRADUATE_EMAIL_SMTP_PORT']
      tls = ENV['GRADUATE_EMAIL_SMTP_TLS']
      user = ENV['GRADUATE_EMAIL_SMTP_USER_NAME']
      password = ENV['GRADUATE_EMAIL_SMTP_PASSWORD']
      auth = ENV['GRADUATE_EMAIL_SMTP_AUTHENTICATION']
      valid_auth = if user.nil? && password.nil? && auth.nil?
        true
      else
        user.is_a?(String) && !user.empty? && !user.match?(/[\r\n\x00]/) &&
          password.is_a?(String) && !password.empty? && !password.match?(/[\r\n\x00]/) && %w[plain login cram_md5].include?(auth)
      end
      @delivery_configured = @from_address && @from_address == sender &&
        host.is_a?(String) && host.match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9.-]{0,251}[a-zA-Z0-9])?\z/) &&
        port.is_a?(String) && port.match?(/\A[0-9]{1,5}\z/) && (1..65535).cover?(port.to_i) &&
        %w[starttls tls].include?(tls) && valid_auth
      @smtp_settings = if @delivery_configured
        {address: host.dup.freeze, port: port.to_i, domain: URI.parse(@base_url.to_s).host || 'localhost',
          user_name: user&.dup&.freeze, password: password&.dup&.freeze, authentication: auth&.to_sym,
          enable_starttls: tls == 'starttls', enable_starttls_auto: false, tls: tls == 'tls' ? true : nil,
          openssl_verify_mode: OpenSSL::SSL::VERIFY_PEER, open_timeout: 3, read_timeout: 3}.freeze
      end
      @from_address&.freeze
      nil
    rescue StandardError
      @delivery_configured = false
      @smtp_settings = nil
      nil
    end

    def configured?
      @configured == true
    end
  end
end

GraduateEmail.configure!
