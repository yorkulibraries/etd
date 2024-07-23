# frozen_string_literal: true

require Rails.root.join('lib/tasks/load_gem_records_csv.rb')

namespace :gem_records_csv do
  desc 'Loading Gem Records.'
  # bundle exec rake "gem_records_csv:load[/full/path/to/gem_records.csv,/full/path/to/committee_members.csv]"

  task :load, [:gem_record_file, :commitee_member_file] => :environment do |t, args|
    if args[:gem_record_file].nil? || args[:commitee_member_file].nil?
      puts "Usage: bundle exec rake \"gem_records_csv:load[/full/path/to/gem_records.csv,/full/path/to/committee_members.csv]\""
      exit 1
    end
    gem_record_filename = args[:gem_record_file].strip
    commitee_member_file = args[:commitee_member_file].strip
    gem_load = LoadGemRecordsCSV.new
    gem_load.load_gem_records(gem_record_filename)
    if !commitee_member_file.nil? || !commitee_member_file.empty?
      gem_load.load_committee_members(commitee_member_file)
    end

  end
end
