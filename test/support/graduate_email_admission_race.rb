# frozen_string_literal: true
# Independent database session. No raw exceptions, tokens, keys or targets cross
# the pipe. Parent releases all children before either enters product locks.
$stdout.sync = true
begin
  require 'json'
  input = JSON.parse($stdin.gets)
  configuration = ActiveRecord::Base.connection_db_config.configuration_hash
  raise 'Database mismatch' unless configuration.slice(:adapter, :database).stringify_keys == input.fetch('database') &&
    ENV['DATABASE_URL'] == ENV['TEST_DATABASE_URL']
  expected = configuration[:adapter] == 'sqlite3' ? Rails.root.join('tmp/graduate-email-storage_test.sqlite3').to_s : 'etd_graduate_email_test'
  raise 'Unsafe database' unless %w[sqlite3 mysql2].include?(configuration[:adapter]) && configuration[:database] == expected
  ENV.update('GRADUATE_EMAIL_BASE_URL' => 'http://127.0.0.1:3210',
    'GRADUATE_EMAIL_CODE_KEY' => 'c' * 32, 'GRADUATE_EMAIL_LIMIT_KEY' => 'l' * 32)
  GraduateEmail.configure!
  # Resolve APIs before READY, giving RED an immediate, static missing-API result.
  GraduateEmail::Challenges
  GraduateEmail::Limits
  ActiveRecord::Base.connection
  puts 'ADMISSION_READY'
  raise 'Barrier missing' unless $stdin.gets&.strip == 'START'
  first_sql = nil
  subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
    sql = payload[:sql]
    first_sql ||= sql if sql.match?(/\A(?:UPDATE|SELECT)/i) && !sql.match?(/sqlite_master|@@|SHOW/i)
  end
  now = Time.iso8601(input.fetch('now'))
  if input.fetch('action') == 'send'
    require 'active_support/testing/time_helpers'
    extend ActiveSupport::Testing::TimeHelpers
    travel_to(now)
    GraduateEmail::Challenges.request!(purpose: :login, browser_token: input.fetch('browser'),
      ip: '192.0.2.1', address: 'approved@example.com')
    puts 'ADMISSION_SENT_REQUEST'
  else
    GraduateEmail::Control.synchronize do
      args = {address_key: GraduateEmail::Limits.address_key(input: 'approved@example.com'),
        student_id: input.fetch('student_id'), ip_key: GraduateEmail::Limits.ip_key(input: '192.0.2.1'), now: now}
      outcome = GraduateEmail::Limits.admit!(kind: :verify, **args)
      GraduateEmail::Limits.record_failure!(**args) if outcome == :allowed
      raise 'Unexpected failure admission' unless outcome == :allowed
    end
    puts 'ADMISSION_COUNTED_FAILURE'
  end
  raise 'Read before control write' unless first_sql&.match?(/\AUPDATE graduate_email_controls SET lock_version/i)
  puts 'ADMISSION_WRITE_FIRST'
rescue NameError => error
  puts "ADMISSION_ERROR missing_api_#{error.name}"
  location = error.backtrace.find { |entry| entry.include?('graduate_email') }
  puts "ADMISSION_LOCATION #{File.basename(location).split(':in').first}" if location
  exit 1
rescue StandardError => error
  puts "ADMISSION_ERROR #{error.class.name.gsub(/[^A-Za-z:]/, '')}"
  location = error.backtrace.find { |entry| entry.include?('graduate_email') }
  puts "ADMISSION_LOCATION #{File.basename(location).split(':in').first}" if location
  exit 1
ensure
  ActiveSupport::Notifications.unsubscribe(subscriber) if defined?(subscriber) && subscriber
end
