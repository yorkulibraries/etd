# frozen_string_literal: true
# Codes/transaction binding arrive through stdin only, never argv or artifacts.
$stdout.sync = true
begin
  config = ActiveRecord::Base.connection_db_config.configuration_hash
  expected = config[:adapter] == 'sqlite3' ? Rails.root.join('tmp/graduate-email-storage_test.sqlite3').to_s : 'etd_graduate_email_test'
  raise GraduateAuthentication::Rejected unless Rails.env.test? && config[:database] == expected && ENV['DATABASE_URL'] == ENV['TEST_DATABASE_URL']
  puts 'RACE_READY'
  data = JSON.parse($stdin.gets)
  puts 'RACE_ATTEMPT'
  result = GraduateEmail::Verification.redeem!(challenge_public_id: data['id'], browser_token: data['browser'], code: data['code'], ip: '192.0.2.1')
  puts(result ? 'RACE_ACCEPTED' : 'RACE_REJECTED')
rescue StandardError
  puts 'RACE_ERROR'
  exit 1
end
