# frozen_string_literal: true

namespace :etd do
  desc 'Loading Gem Records.'

  task import_file: :environment do
    filename = ENV['file']
    thesis_id = ENV['thesis']
    username = ENV['username']

    thesis = Thesis.find_by_id(thesis_id)
    user = User.find_by_username(username)

    if filename.nil? || !File.exist?(filename) || thesis.nil? || user.nil?
      puts '==========================='
      puts "Usage: rake etd:import_file username=yourusername thesis=1234 file=/path/to/file name='name this file'"
      puts '------'
      puts 'file: Path to a file to be imported.'
      puts 'name: Name this file, in quotes, optional.'
      puts 'thesis: Valid, existing ID of the thesis.'
      puts 'username: Your PPY username'
      puts '==========================='
      exit
    end

    name = ENV['name'] || File.basename(filename)

    doc = Document.new
    doc.supplemental = true
    doc.file = File.open(filename)
    doc.thesis = thesis
    doc.user = user
    doc.name = name

    doc.save!
  end
end
