# frozen_string_literal: true
# Test-only process hooks. Product never knows about barriers or capture pipes.
raise 'Test helper unavailable' unless Rails.env.test?
require 'json'
require 'socket'
$stdout.sync = true
begin
  input = JSON.parse($stdin.gets)
  config = ActiveRecord::Base.connection_db_config.configuration_hash
  expected = config[:adapter] == 'sqlite3' ? Rails.root.join('tmp/graduate-email-storage_test.sqlite3').to_s : 'etd_graduate_email_test'
  raise 'Unsafe worker database' unless config.slice(:adapter, :database).stringify_keys == input.fetch('database') &&
    config[:database] == expected && ENV['DATABASE_URL'] == ENV['TEST_DATABASE_URL']
  ENV.update('GRADUATE_EMAIL_BASE_URL' => 'http://127.0.0.1:3210',
    'GRADUATE_EMAIL_CODE_KEY' => 'c' * 32, 'GRADUATE_EMAIL_LIMIT_KEY' => 'l' * 32,
    'GRADUATE_EMAIL_FROM' => 'authentication@example.org', 'GRADUATE_EMAIL_SMTP_ADDRESS' => 'relay.example.org',
    'GRADUATE_EMAIL_SMTP_PORT' => '587', 'GRADUATE_EMAIL_SMTP_TLS' => 'starttls')
  GraduateEmail.configure!
  GraduateEmail::Delivery
  channel = UNIXSocket.for_fd(3)
  barrier = input.fetch('barrier')
  rendezvous = ->(stage) do
    if barrier == stage
      puts "DELIVERY_BARRIER #{stage}"
      raise 'Barrier protocol' unless $stdin.gets&.strip == 'CONTINUE'
    end
  end
  GraduateEmailChallenge.after_update do
    rendezvous.call('before_claim_commit') if saved_change_to_state? && state == 'claimed'
  end
  hooks = Module.new do
    define_method(:claim!) do |**args|
      result = super(**args)
      rendezvous.call('after_claim') if result
      result
    end
    define_method(:authorize_send!) do |**args|
      result = super(**args)
      rendezvous.call('after_authorization') if result
      result
    end
    define_method(:finalize!) do |**args|
      result = super(**args)
      rendezvous.call('after_sent') if args[:outcome] == :sent
      result
    end
  end
  GraduateEmail::Delivery.singleton_class.prepend(hooks)
  transport = Class.new do
    attr_reader :settings
    define_method(:initialize) { |settings| @settings = settings }
    define_method(:deliver!) do |message|
      raise 'SMTP lock held' unless ActiveRecord::Base.connection.open_transactions.zero?
      Marshal.dump(message.encoded, channel)
      channel.flush
      puts 'DELIVERY_NETWORK'
      result = channel.gets&.strip
      raise IOError, message.encoded if result == 'ERROR'
      raise 'Transport protocol' unless result == 'ACCEPT'
      rendezvous.call('after_acceptance')
    end
  end
  GraduateAuthenticationMailer.define_singleton_method(:transport_class) { transport }
  puts 'DELIVERY_READY'
  raise 'Start protocol' unless $stdin.gets&.strip == 'START'
  result = Delayed::Worker.new(queues: ['graduate_email']).work_off(input.fetch('limit'))
  raise 'Worker failed' unless result.last.zero?
  puts 'DELIVERY_DONE'
rescue StandardError => error
  puts "DELIVERY_ERROR #{error.class.name.gsub(/[^A-Za-z:]/, '')}"
  location = error.backtrace.find { |entry| entry.include?('graduate_email') }
  puts "DELIVERY_LOCATION #{File.basename(location).split(':in').first}" if location
  exit 1
ensure
  channel&.close if defined?(channel)
end
