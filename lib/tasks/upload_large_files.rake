# frozen_string_literal: true

namespace :etd do
  desc 'Loading Gem Records.'
  # Usage: rake etd:upload_file THESIS_ID=id ADMIN_ID=id  FILE=filepath

  @thesis_id = nil
  @admin_user_id = nil
  @file_path = nil

  task upload_file: :environment do
    unless valid_args?
      puts "ERROR: Missing arguments, \n\nTHESIS_ID=#{@thesis_id}  \nADMIN_ID=#{@admin_user_id}  \nFILE=#{@file_path}"
      exit
    end

    # find the thesis, user and file
    thesis = Thesis.find_by_id(@thesis_id)
    admin = User.active.not_students.admins.find_by_id(@admin_user_id)

    if thesis.nil?
      puts "ERROR: Thesis not found. ID: #{@thesis_id}"
      exit
    end

    if admin.nil? || admin.role != User::ADMIN
      puts "ERROR: Admin user not found. ID: #{@admin_user_id}.\n\nYou must use an ADMIN user id to upload this file"
      exit
    end

    unless File.exist?(@file_path)
      puts "ERROR: File doesn't exist. FILE: #{@file_path}. Please provide correct file path"
      exit
    end

    # everything is good, lets upload
    puts '======='
    puts "Uploading supplemental file: (#{@file_path}) to [#{thesis.title}] using {#{admin.name}'s} account"

    d = Document.new(supplemental: true)
    d.thesis = thesis
    d.user = admin
    d.name = File.basename(@file_path)
    d.file = File.new(@file_path)
    d.save

    puts "Uploaded file: #{@file_path}"
  end

  def valid_args?
    @thesis_id = ENV['THESIS_ID']
    @admin_user_id = ENV['ADMIN_ID']
    @file_path = ENV['FILE']

    if @thesis_id.nil? || @admin_user_id.nil? || @file_path.nil?
      false
    else

      true
    end
  end
end
