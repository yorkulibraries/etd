require Rails.root.join('lib/etd/exporter.rb')
require 'ostruct'

OPTIONS = {
  username: "#{ENV['USERNAME']}", password: "#{ENV['PASSWORD']}",
  service_document_url: "#{ENV['DSPACE']}/server/swordv2/servicedocument",
  collection_uri: "#{ENV['DSPACE']}/server/swordv2/collection/#{ENV['HANDLE']}",
  collection_title: "#{ENV['COLLECTION']}"
}

module DspaceExporter
  def self.theses_for(thesis_id: nil, thesis_any_id: nil, publish_date: EmbargoRequest.toronto_today)
    base = Thesis.publication_eligible

    if thesis_id.present?
      base.where(status: Thesis::ACCEPTED, id: thesis_id)
    elsif thesis_any_id.present?
      base.where(id: thesis_any_id)
    else
      base.where(status: Thesis::ACCEPTED).where('published_date <= ?', publish_date)
    end
  end
end

namespace :dspace do
  desc "Deposit to YorkSpace"

  task export: :environment do
    log "Exporting to DSPACE"
    log "COMPLETE_THESIS: #{ENV['COMPLETE_THESIS']}  PUBLISH_DATE: #{ENV['PUBLISH_DATE']}"

    zipped = ENV['ZIPPED']=='true'

    failed_deposits = Array.new
    options = get_options()
    log options

    exporter = ETD::Exporter.new options
    exporter.prepare_collection

    # three things to do

    # THESIS_ANY bypasses status for diagnostics, but never publication eligibility.
    selector = DspaceExporter.theses_for(thesis_id: ENV['THESIS'], thesis_any_id: ENV['THESIS_ANY'],
                                         publish_date: publish_date)
    theses = selector

    log "FOUND: #{theses.size} theses"

    # 2) publish each thesis and its files, while mapping thesis to Atom Entry
    theses.each_with_index do |thesis, index|

      begin
        log "\n========== Depositing ========="
        log "#{index + 1} of #{theses.size} [Thesis ID: #{thesis.id}, Student ID: #{thesis.student.id}]"

        entry = thesis_to_atom_entry(thesis)
        files = extract_thesis_filepaths(thesis)

        unless selector.where(id: thesis.id).exists?
          log "Skipping Thesis ID #{thesis.id}: no longer publication eligible."
          next
        end

        receipt = exporter.deposit(entry: entry, files: files, zipped: zipped, complete: complete_thesis?)

        log("Deposited. status_code:  #{receipt.status_code}. status_message:  #{receipt.status_message}")

        # 3) set status of each thesis to publish after it has been published
        if (receipt != nil)
          thesis.publish if publish_thesis?
        end

        log "======================"
      rescue Exception => e
        log ("Error: #{e}")
  puts e.backtrace
        failed_deposits.push(thesis)
        error(thesis, e)
      end

      STDOUT.write "\rProcessed: #{index + 1} of #{theses.size}. \nFailed: #{failed_deposits.size}"

      if ENV["OUTPUT_XML"]
        log(entry.to_s)
      end

      sleep(5)
    end

    if failed_deposits.size > 0
      STDERR.puts("\n\nFailed: #{failed_deposits.size}, see logged output.")
    end

    ## Run Temp file clean up
    Dir.glob('/tmp/etd-*.zip').each { |f| File.delete(f) }

  end

  # Maps thesis to atom entry
  def thesis_to_atom_entry(thesis)
    entry = Atom::Entry.new
    entry.add_dublin_core_extension!("title", thesis.title)
    entry.add_dublin_core_extension!("creator", thesis.author)

    thesis.supervisor.split("/").map(&:strip).each do | supervisor |
      entry.add_dublin_core_extension!("supervisor", supervisor)
    end


    thesis.loc_subjects.each do |subject|
      entry.add_dublin_core_extension!("subject", subject.name)
    end

    if thesis.keywords != nil
      thesis.keywords.split(",").each do |keyword|
        entry.add_dublin_core_extension!("relationSubjectKeywords", keyword.strip)
      end
    end

    entry.add_dublin_core_extension!("abstract", thesis.abstract.tr("\u0002\u000B\u000C\u000E\u000F",''))
    entry.add_dublin_core_extension!("language", language_to_iso(thesis.language))
    entry.add_dublin_core_extension!("name", thesis.degree_name_full)
    entry.add_dublin_core_extension!("level", thesis.degree_level)

    entry.add_dublin_core_extension!("discipline", short_program_name(thesis.program))
    entry.add_dublin_core_extension!("issued", Date.current.strftime("%Y-%m-%d"))
    entry.add_dublin_core_extension!("dateCopyrighted", thesis.exam_date.strftime("%Y-%m-%d"))
    entry.add_dublin_core_extension!("date.copyright", thesis.exam_date.strftime("%Y-%m-%d"))

    entry.add_dublin_core_extension!("type", "Electronic Thesis or Dissertation")
    entry.add_dublin_core_extension!("rights", "Author owns copyright, except where explicitly noted. Please contact the author directly with licensing requests.")

    return entry
  end

  def language_to_iso(language)
    language = "" if language.blank?

    iso = case language.downcase
    when "en", "english", "eng"
       "en"
    when "fr", "french"
      "fr"
    else
      "other"
    end

    return iso
  end

  def short_program_name(program)
    if program != nil && program.is_a?(String)
      program.split(".,").last.strip
    else
      program
    end
  end

  # Go through documents and get the file paths
  def extract_thesis_filepaths(thesis)
    return [] if thesis == nil

    files = []
    thesis.documents.not_deleted.where(usage: Document.usages[:thesis], embargo_request_id: nil).where(supplemental: false).each do |document|
      log "       #{document.file.path}"
      files.push document.file.path
    end

    unless ENV["PRIMARY_FILES_ONLY"] == "true"
      thesis.documents.not_deleted.where(usage: Document.usages[:thesis], embargo_request_id: nil, supplemental: true).each do |document|
        log "       #{document.file.path}"
        files.push document.file.path
      end
    end

    return files
  end

  # Which options to load
  def get_options()
      return OPTIONS
  end

  def complete_thesis?
    # Allow thesis to be marked as completed or not

    if ENV['COMPLETE_THESIS'] == "true"
      true
    else
      false
    end
  end

  def publish_thesis?
    if ENV["PUBLISH"] == "true"
      true
    else
      false
    end
  end

  def publish_date
    if ENV['PUBLISH_DATE'] == nil
      EmbargoRequest.toronto_today
    else
      ENV["PUBLISH_DATE"]
    end
  end

  # Crude logging
  def log(string)
    if ENV['DEBUG'] != nil
      puts string
    end
  end

  def error(thesis, exception)
    STDERR.puts "======= DEPOSIT ERROR ======="
    STDERR.puts "TID: #{thesis.id}   UID: #{thesis.student.id}  Error: #{exception.message}" rescue nil
    STDERR.puts exception
    STDERR.puts "=============================\n"
  end
end
