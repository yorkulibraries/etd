# frozen_string_literal: true

require Rails.root.join('lib/tasks/load_gem_records.rb')

namespace :gem_records do
  desc 'Loading Gem Records.'
  # Usage: cat /file/with/gem_records.txt | rake gem_records:load

  task load: :environment do
    GemRecord.delete_all
    gem_load = LoadGemRecords.new
    gem_load.load_stdin
  end
end
