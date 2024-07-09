# frozen_string_literal: true

require Rails.root.join('lib/tasks/load_gem_records_csv.rb')

namespace :gem_records_csv do
  desc 'Loading Gem Records.'
  # Usage: cat /file/with/gem_records.txt | rake gem_records:load

  task :load, [:filename] => :environment do |t, args|
    filename = args[:filename]
    if filename.nil? || filename.empty?
      puts "Error: Filename is required"
      exit 1
    end
    GemRecord.delete_all
    gem_load = LoadGemRecordsCSV.new
    gem_load.load_csv(filename)
  end
end
