# frozen_string_literal: true

# For developers: theses whose YorkSpace send may or may not have worked are held back by the website
# export until someone looks in YorkSpace and records what they found.
namespace :dspace do
  namespace :attempts do
    desc 'List YorkSpace sends that are in progress or need checking'
    task list: :environment do
      attempts = ThesisDepositAttempt.unresolved.includes(:thesis).order(:id)
      puts 'Nothing needs checking.' if attempts.empty?
      attempts.each do |attempt|
        puts "Attempt #{attempt.id}: thesis #{attempt.thesis_id} (#{attempt.thesis.title}), export #{attempt.export_log_id}, " \
             "#{attempt.state}, started #{attempt.created_at}"
        puts "  SWORD location: #{attempt.sword_location.presence || 'none'}"
        puts "  Problem: #{attempt.error_message}"
      end
    end

    desc 'Record what YorkSpace shows for a held send. OUTCOME=in_yorkspace marks the thesis published; ' \
         'OUTCOME=not_in_yorkspace lets the next export send it'
    task :resolve, %i[attempt_id outcome] => :environment do |_task, args|
      attempt = ThesisDepositAttempt.unresolved.find(args[:attempt_id])
      case args[:outcome]
      when 'in_yorkspace'
        abort "Thesis #{attempt.thesis_id} could not be marked published (it may be blocked)." unless attempt.thesis.publish
        attempt.update!(state: ThesisDepositAttempt::SENT, open_thesis_id: nil,
                        error_message: "#{attempt.error_message} Checked: in YorkSpace.")
        puts "Thesis #{attempt.thesis_id} marked published. Add its licences in YorkSpace if they are missing."
      when 'not_in_yorkspace'
        attempt.update!(state: ThesisDepositAttempt::FAILED, open_thesis_id: nil,
                        error_message: "#{attempt.error_message} Checked: not in YorkSpace.")
        puts "Thesis #{attempt.thesis_id} will be sent by the next export."
      else
        abort 'OUTCOME must be in_yorkspace or not_in_yorkspace'
      end
    end
  end
end
