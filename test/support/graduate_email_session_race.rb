# frozen_string_literal: true
# Isolated process for Task 2 lock-order proof. Rails runner loads the application
# with the guarded adapter environment. The pipe protocol contains no secrets.
$stdout.sync = true
method, action, student_id, connection_id, identity_id, actor_id, expected_json = ARGV
begin
  configuration = ActiveRecord::Base.connection_db_config.configuration_hash
  expected_configuration = JSON.parse(expected_json)
  raise 'Mismatched race database' unless configuration.slice(:adapter, :database).stringify_keys == expected_configuration
  raise 'Unsafe race database' unless %w[sqlite3 mysql2].include?(configuration[:adapter]) && configuration[:database].include?('test')
  if ENV['GRADUATE_EMAIL_PROJECT_ROOT']
    expected = configuration[:adapter] == 'sqlite3' ? Rails.root.join('tmp/graduate-email-storage_test.sqlite3').to_s : 'etd_graduate_email_test'
    raise 'Mismatched race database' unless configuration[:database] == expected &&
      ENV['DATABASE_URL'] == ENV['TEST_DATABASE_URL'] && configuration[:adapter] == ENV['DB_ADAPTER']
  end
  ActiveRecord::Base.connection
  puts 'RACE_READY'
  raise 'Missing barrier' unless $stdin.gets&.strip == 'START'
  puts 'RACE_ATTEMPT'
  if action == 'disable'
    GraduateEmail::Control.set_enabled!(enabled: false, actor_id: actor_id.to_i)
  elsif action == 'block'
    Student.find(student_id).block
  elsif method == 'email'
    GraduateEmail::Control.synchronize do |control|
      GraduateSession.issue_email!(connection: GraduateEmailConnection.find(connection_id), generation: control.generation)
    end
  else
    GraduateSession.issue!(GraduateIdentity.find(identity_id))
  end
  puts 'RACE_ACCEPTED'
rescue GraduateAuthentication::Rejected
  puts 'RACE_REJECTED'
rescue StandardError
  puts 'RACE_ERROR'
  exit 1
end
