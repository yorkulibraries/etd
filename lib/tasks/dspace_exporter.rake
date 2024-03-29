# frozen_string_literal: true

require Rails.root.join('lib/etd/exporter.rb')
require 'ostruct'

OPTIONS = {
  username: (ENV['USERNAME']).to_s, password: (ENV['PASSWORD']).to_s,
  service_document_url: "#{ENV['DSPACE']}/server/swordv2/servicedocument",
  collection_uri: "#{ENV['DSPACE']}/server/swordv2/collection/#{ENV['HANDLE']}",
  collection_title: (ENV['COLLECTION']).to_s
}.freeze

namespace :dspace do
  desc 'Deposit to YorkSpace'

  task export: :environment do
    log 'Exporting to DSPACE'
    log "COMPLETE_THESIS: #{ENV['COMPLETE_THESIS']}  PUBLISH_DATE: #{ENV['PUBLISH_DATE']}"

    zipped = ENV['ZIPPED'] == 'true'

    failed_deposits = []
    options = get_options
    log options

    exporter = ETD::Exporter.new options
    exporter.prepare_collection

    # three things to do

    # 1) get unpublished theses, that don't have embargo placed on them.
    theses = if !ENV['THESIS'].nil?
               Thesis.accepted.without_embargo.where(id: ENV['THESIS'])
             elsif !ENV['THESIS_ANY'].nil?
               Thesis.where(id: ENV['THESIS_ANY'])
             else
               Thesis.accepted.without_embargo.where(published_date: publish_date)
             end

    log "FOUND: #{theses.size} theses"

    # 2) publish each thesis and its files, while mapping thesis to Atom Entry
    theses.each_with_index do |thesis, index|
      begin
        log "\n========== Depositing ========="
        log "#{index + 1} of #{theses.size} [Thesis ID: #{thesis.id}, Student ID: #{thesis.student.id}]"

        entry = thesis_to_atom_entry(thesis)
        files = extract_thesis_filepaths(thesis)

        receipt = exporter.deposit(entry:, files:, zipped:, complete: complete_thesis?)

        log("Deposited: #{receipt.status_code}: #{receipt.status_message}")

        # 3) set status of each thesis to publish after it has been published
        thesis.publish if !receipt.nil? && publish_thesis?

        log '======================'
      rescue Exception => e
        log("Error: #{e}")
        puts e.backtrace
        failed_deposits.push(thesis)
        error(thesis, e)
      end

      $stdout.write "\rProcessed: #{index + 1} of #{theses.size}. \nFailed: #{failed_deposits.size}"

      log(entry.to_s) if ENV['OUTPUT_XML']

      sleep(5)
    end

    warn("\n\nFailed: #{failed_deposits.size}, see logged output.") if failed_deposits.size.positive?

    ## Run Temp file clean up
    Dir.glob('/tmp/etd-*.zip').each { |f| File.delete(f) }
  end

  # Maps thesis to atom entry
  def thesis_to_atom_entry(thesis)
    entry = Atom::Entry.new
    entry.add_dublin_core_extension!('title', thesis.title)
    entry.add_dublin_core_extension!('creator', thesis.author)

    thesis.supervisor.split('/').map(&:strip).each do |supervisor|
      entry.add_dublin_core_extension!('supervisor', supervisor)
    end

    thesis.loc_subjects.each do |subject|
      entry.add_dublin_core_extension!('subject', subject.name)
    end

    thesis.keywords&.split(',')&.each do |keyword|
      entry.add_dublin_core_extension!('relationSubjectKeywords', keyword.strip)
    end

    entry.add_dublin_core_extension!('abstract', thesis.abstract)
    entry.add_dublin_core_extension!('language', language_to_iso(thesis.language))
    entry.add_dublin_core_extension!('name', Thesis::DEGREENAME_FULL[thesis.degree_name])
    entry.add_dublin_core_extension!('level', thesis.degree_level)

    entry.add_dublin_core_extension!('discipline', short_program_name(thesis.program))
    entry.add_dublin_core_extension!('issued', Date.current.strftime('%Y-%m-%d'))
    entry.add_dublin_core_extension!('dateCopyrighted', thesis.exam_date.strftime('%Y-%m-%d'))

    entry.add_dublin_core_extension!('type', 'Electronic Thesis or Dissertation')
    entry.add_dublin_core_extension!('rights',
                                     'Author owns copyright, except where explicitly noted. Please contact the author directly with licensing requests.')

    entry
  end

  def language_to_iso(language)
    language = '' if language.blank?

    case language.downcase
    when 'en', 'english', 'eng'
      'en'
    when 'fr', 'french'
      'fr'
    else
      'other'
    end
  end

  def short_program_name(program)
    if !program.nil? && program.is_a?(String)
      program.split('.,').last.strip
    else
      program
    end
  end

  # Go through documents and get the file paths
  def extract_thesis_filepaths(thesis)
    return [] if thesis.nil?

    files = []
    thesis.documents.primary.not_deleted.where(usage: :thesis).each do |document|
      log "       #{document.file.path}"
      files.push document.file.path
    end

    unless ENV['PRIMARY_FILES_ONLY'] == 'true'
      thesis.documents.supplemental.not_deleted.where(usage: :thesis).each do |document|
        log "       #{document.file.path}"
        files.push document.file.path
      end
    end

    files
  end

  # Which options to load
  def get_options
    OPTIONS
  end

  def complete_thesis?
    # Allow thesis to be marked as completed or not

    ENV['COMPLETE_THESIS'] == 'true'
  end

  def publish_thesis?
    ENV['PUBLISH'] == 'true'
  end

  def publish_date
    if ENV['PUBLISH_DATE'].nil?
      Time.now.strftime('%Y-%m-%d')
    else
      ENV['PUBLISH_DATE']
    end
  end

  # Crude logging
  def log(string)
    return if ENV['DEBUG'].nil?

    puts string
  end

  def error(thesis, exception)
    warn '======= DEPOSIT ERROR ======='
    begin
      warn "TID: #{thesis.id}   UID: #{thesis.student.id}  Error: #{exception.message}"
    rescue StandardError
      nil
    end
    warn exception
    warn "=============================\n"
  end
end
