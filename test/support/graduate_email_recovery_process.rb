# frozen_string_literal: true
# Private stdin contains test-only binding/code. Static stdout only.
raise 'Test only' unless Rails.env.test?
require 'json'
$stdout.sync = true
begin
  data = JSON.parse($stdin.gets)
  config = ActiveRecord::Base.connection_db_config.configuration_hash
  expected = config[:adapter] == 'sqlite3' ? Rails.root.join('tmp/graduate-email-storage_test.sqlite3').to_s : 'etd_graduate_email_test'
  raise 'Unsafe database' unless config[:database] == expected && ENV['DATABASE_URL'] == ENV['TEST_DATABASE_URL']
  ENV.update('GRADUATE_EMAIL_BASE_URL' => 'http://127.0.0.1:3210', 'GRADUATE_EMAIL_CODE_KEY' => 'c' * 32, 'GRADUATE_EMAIL_LIMIT_KEY' => 'l' * 32)
  GraduateEmail.configure!
  puts 'RECOVERY_READY'
  raise 'Barrier' unless $stdin.gets&.strip == 'START'
  # Barrier ends BEFORE opening any product transaction. No synthetic clock.
  result = case data.fetch('action')
  when 'verify'
    GraduateEmail::Verification.redeem!(challenge_public_id: data['id'], browser_token: data['browser'], code: data['code'], ip: '192.0.2.1')
  when 'revoke'
    GraduateEmail::Revocation.connection!(connection: GraduateEmailConnection.find(data['connection']), actor: User.find(data['actor']), impersonating: false)
    true
  when 'disable'
    GraduateEmail::Control.set_enabled!(enabled: false, actor_id: data['actor'])
    true
  when 'reissue'
    GraduateEmail::Enrollment.issue!(student: Student.find(data['student']), actor: User.find(data['actor']), address: 'reissued@example.com', confirmed_address: 'reissued@example.com', identity_verified: true, impersonating: false, replacement: true)
  when 'deliver'
    # RAM-only transport: a queued job that wins may send locally, never SMTP.
    transport = Class.new do
      def initialize(*); end
      def deliver!(_message)
        raise 'Transport under lock' unless ActiveRecord::Base.connection.open_transactions.zero?
      end
    end
    GraduateAuthenticationMailer.define_singleton_method(:transport_class) { transport }
    GraduateEmail::Delivery.perform!(challenge_public_id: data['id'])
    true
  end
  puts(result ? 'RECOVERY_ACCEPTED' : 'RECOVERY_REJECTED')
rescue StandardError => error
  puts "RECOVERY_ERROR #{error.class.name.gsub(/[^A-Za-z:]/, '')}"
  exit 1
end
