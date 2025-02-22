# frozen_string_literal: true

require Rails.root.join('lib/tasks/load_gem_records_csv.rb')

namespace :gem_records_csv do
  desc 'Loading Gem Records.'
  # bundle exec rake gem_records_csv:load  GEM_RECORDS=/home/etd/gem_records.csv COMMITEE_MEMBERS=/home/etd/committee_members.csv]

  task :load, [:gem_record_file, :commitee_member_file] => :environment do |t, args|
    gem_record_file = ENV['GEM_RECORDS']
    commitee_member_file = ENV['COMMITEE_MEMBERS']

    gem_load = LoadGemRecordsCSV.new
    gem_load.load_gem_records(gem_record_file)
    if !commitee_member_file.nil? || !commitee_member_file.empty?
      gem_load.load_committee_members(commitee_member_file)
    end

  end
end
