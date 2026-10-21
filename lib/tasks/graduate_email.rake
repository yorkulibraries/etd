# frozen_string_literal: true
require 'json'
namespace :graduate_email do
  # stdout is an enum/count-only JSON record, including failure paths. Never
  # abort with an underlying exception, database URL, actor, address or payload.
  command = lambda do |&block|
    begin
      puts JSON.generate(block.call)
    rescue StandardError
      puts JSON.generate(result: 'rejected')
      exit 1
    end
  end
  desc 'Graduate email status (enum/count-only)'
  task status: :environment do
    command.call do
      result = GraduateEmail::Operations.status
      raise GraduateAuthentication::Rejected if result[:control] == 'unavailable'
      result
    end
  end
  %w[enable disable].each do |action|
    desc "#{action.capitalize} graduate email using protected GRADUATE_EMAIL_OPERATOR_ID"
    task action => :environment do
      command.call do
        GraduateEmail::Operations.transition!(enabled: action == 'enable', operator: ENV['GRADUATE_EMAIL_OPERATOR_ID'])
        GraduateEmail::Operations.status
      end
    end
  end
  desc 'Bounded graduate email retention cleanup (safe while disabled)'
  task cleanup: :environment do
    command.call { GraduateEmail::Cleanup.call.merge(result: 'ok') }
  end
end
