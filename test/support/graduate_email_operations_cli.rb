# frozen_string_literal: true
# Test-only barrier before the actual registered operator rake task.
raise 'Test helper unavailable' unless Rails.env.test?
$stdout.sync = true
begin
  config = ActiveRecord::Base.connection_db_config.configuration_hash
  expected = config[:adapter] == 'sqlite3' ? Rails.root.join('tmp/graduate-email-storage_test.sqlite3').to_s : 'etd_graduate_email_test'
  raise 'Unsafe command database' unless config[:database] == expected && ENV['DATABASE_URL'] == ENV['TEST_DATABASE_URL']
  Rails.application.load_tasks
  puts 'COMMAND_READY'
  raise 'Start protocol' unless $stdin.gets&.strip == 'START'
  puts 'COMMAND_ATTEMPT'
  Rake::Task['graduate_email:disable'].invoke
  puts 'COMMAND_DONE'
rescue StandardError
  puts 'COMMAND_REJECTED'
  exit 1
end
