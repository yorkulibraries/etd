# frozen_string_literal: true

require Rails.root.join('lib/tasks/load_gem_records_csv.rb')

namespace :gem_records_csv do
  desc 'Loading Gem Records.'
  # Usage: cat /file/with/gem_records.txt | rake gem_records:load

  task :load, [:gem_record_file, :commitee_member_file] => :environment do |t, args|
    gem_record_filename = Rails.root.join(args[:gem_record_file])
    commitee_member_file = Rails.root.join(args[:commitee_member_file])
    if gem_record_filename.nil? || gem_record_filename.empty?
      puts "Error: Gem Record Filename is required"
      exit 1
    end
    #GemRecord.delete_all
    gem_load = LoadGemRecordsCSV.new
    gem_load.load_gem_records(gem_record_filename)
    if !commitee_member_file.nil? || !commitee_member_file.empty?
      gem_load.load_committee_members(commitee_member_file)
    end

  end
end
