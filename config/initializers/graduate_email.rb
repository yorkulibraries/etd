# frozen_string_literal: true

require 'ipaddr'
require 'openssl'
require 'uri'
# Initializers run before the main autoloader is ready. Validate sender on a
# fresh CLI/worker boot too, rather than rescuing an unavailable parser.
require Rails.root.join('app/services/graduate_email/address')

# Configuration is deliberately independent of Google and never queries feature
# tables during boot (including a pre-migration or rolled-back deployment).
module GraduateEmail
  # Unencrypted delivery (GRADUATE_EMAIL_SMTP_TLS=none) exists only for staging
  # test mailboxes such as mailcatcher. It is refused for this site address,
  # for any relay outside a private network, and whenever credentials are set.
  PRODUCTION_HOST = 'etd.library.yorku.ca'
  PRIVATE_RELAY_NETWORKS = %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8].map { |cidr| IPAddr.new(cidr) }.freeze

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
        (%w[starttls tls].include?(tls) || (tls == 'none' && plain_test_relay?(host, user, password, auth))) && valid_auth
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

    private

    def plain_test_relay?(host, user, password, auth)
      site = URI.parse(@base_url.to_s).host
      return false if site.blank? || site.downcase == PRODUCTION_HOST || [user, password, auth].any?
      return false unless host.match?(/\A[0-9]{1,3}(?:\.[0-9]{1,3}){3}\z/)

      address = IPAddr.new(host)
      address.ipv4? && PRIVATE_RELAY_NETWORKS.any? { |network| network.include?(address) }
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end

GraduateEmail.configure!
