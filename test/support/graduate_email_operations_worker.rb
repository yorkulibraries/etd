# frozen_string_literal: true
# Private RAM fake SMTP around the ACTUAL installed foreground jobs:work task.
raise 'Test helper unavailable' unless Rails.env.test?
require 'json'
require 'socket'
$stdout.sync=true
begin
  input=JSON.parse($stdin.gets)
  config=ActiveRecord::Base.connection_db_config.configuration_hash
  expected=config[:adapter]=='sqlite3' ? Rails.root.join('tmp/graduate-email-storage_test.sqlite3').to_s : 'etd_graduate_email_test'
  raise 'Unsafe worker database' unless config.slice(:adapter,:database).stringify_keys==input.fetch('database') && config[:database]==expected && ENV['DATABASE_URL']==ENV['TEST_DATABASE_URL']
  ENV.update('GRADUATE_EMAIL_BASE_URL'=>'https://graduate.example.org','GRADUATE_EMAIL_CODE_KEY'=>'c'*32,
    'GRADUATE_EMAIL_LIMIT_KEY'=>'l'*32,'GRADUATE_EMAIL_FROM'=>'authentication@example.org',
    'GRADUATE_EMAIL_SMTP_ADDRESS'=>'relay.example.org','GRADUATE_EMAIL_SMTP_PORT'=>'587','GRADUATE_EMAIL_SMTP_TLS'=>'starttls')
  GraduateEmail.configure!
  channel=UNIXSocket.for_fd(3)
  barrier=input.fetch('barrier')
  rendezvous=-> do
    if barrier=='claimed'
      puts 'DELIVERY_BARRIER claimed'
      raise 'Continue protocol' unless $stdin.gets&.strip=='CONTINUE'
    end
  end
  hooks=Module.new do
    define_method(:claim!) do |**args|
      result=super(**args)
      rendezvous.call if result
      result
    end
  end
  GraduateEmail::Delivery.singleton_class.prepend(hooks)
  transport=Class.new do
    attr_reader :settings
    define_method(:initialize){|settings| @settings=settings}
    define_method(:deliver!) do |message|
      raise 'SMTP lock held' unless ActiveRecord::Base.connection.open_transactions.zero?
      rendezvous.call unless message.body.decoded.include?('Your sign-in code is ')
      Marshal.dump(message.encoded,channel); channel.flush
      puts 'DELIVERY_NETWORK'
      raise 'Transport protocol' unless channel.gets&.strip=='ACCEPT'
    end
  end
  GraduateAuthenticationMailer.define_singleton_method(:transport_class){transport}
  Rails.application.load_tasks
  # Same launcher and QUEUES as service; read settings after task parsing too.
  Rake::Task['jobs:environment_options'].invoke
  raise 'Worker runtime bounds' unless Delayed::Worker.max_run_time==30 && Delayed::Worker.max_attempts==1
  puts 'DELIVERY_READY'
  raise 'Start protocol' unless $stdin.gets&.strip=='START'
  Rake::Task['jobs:work'].invoke
  puts 'DELIVERY_DONE'
rescue StandardError => error
  puts "DELIVERY_ERROR #{error.class.name.gsub(/[^A-Za-z:]/,'')}"
  exit 1
ensure
  channel&.close if defined?(channel)
end
