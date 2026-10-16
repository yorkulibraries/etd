# frozen_string_literal: true
raise 'Test helper unavailable' unless Rails.env.test?
require_relative 'graduate_email_admission_helpers'
require 'socket'
require 'minitest/mock'
require 'timeout'

module GraduateEmailDeliveryHelpers
  def self.included(base)
    base.include GraduateEmailAdmissionHelpers
  end

  def setup_delivery
    setup_admission
    @delivery_env = ENV.to_h.select { |key, _| key.start_with?('GRADUATE_EMAIL_SMTP_', 'GRADUATE_EMAIL_FROM') }
    ENV.update('GRADUATE_EMAIL_FROM' => 'authentication@example.org',
      'GRADUATE_EMAIL_SMTP_ADDRESS' => 'relay.example.org', 'GRADUATE_EMAIL_SMTP_PORT' => '587',
      'GRADUATE_EMAIL_SMTP_TLS' => 'starttls')
    GraduateEmail.configure!
    @mail_messages = []
    @codes = {}
    test = self
    @transport = Class.new do
      attr_reader :settings
      define_method(:initialize) { |settings| @settings = settings }
      define_method(:deliver!) do |message|
        raise 'Network under transaction' unless ActiveRecord::Base.connection.open_transactions.zero?
        test.capture_message(message)
      end
    end
  end

  def teardown_delivery
    @codes&.clear
    @mail_messages&.clear
    ENV.keys.grep(/\AGRADUATE_EMAIL_(?:SMTP_|FROM)/).each { |key| ENV.delete(key) }
    ENV.update(@delivery_env || {})
    teardown_admission
  end

  def capture_message(message)
    @mail_messages << message
    body = message.body.decoded
    code = body[/^Your sign-in code is ([0-9]{6})\.$/, 1]
    id = @capturing_id
    @codes[id] = code if id && code
  end

  def deliver_row(row)
    @capturing_id = row.public_id
    GraduateAuthenticationMailer.stub(:transport_class, @transport) do
      GraduateEmail::Delivery.perform!(challenge_public_id: row.public_id)
    end
  ensure
    @capturing_id = nil
  end

  def eligible?(row)
    GraduateEmail::Control.synchronize do
      !!GraduateEmail::Delivery.eligible_challenge_locked!(challenge_public_id: row.public_id,
        states: %w[sending sent], now: Time.current)
    end
  end

  def matches?(row, code)
    GraduateEmail::Delivery.code_matches?(challenge: row.reload, code: code)
  end

  def assert_safe_absent(text, *secrets)
    assert secrets.compact.all? { |secret| !text.include?(secret) }, 'Sensitive value escaped'
  end
end
