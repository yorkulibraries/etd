require Rails.root.join('lib/etd/exporter.rb')
require 'ostruct'

class DspaceExportJob < ActiveJob::Base
  attr_accessor :export_log, :sleep_interval, :exporter

  queue_as "dspace_export"


  def initialize(*args)
    super(*args)

    @export_log = nil
    @sleep_interval = 1
    @exporter = nil

  end


  def perform(export_log_id)
    @export_log = ExportLog.find_by_id(export_log_id)
    return if @export_log == nil

    if @exporter == nil
      @exporter = ETD::Exporter.new(settings(@export_log.production_export?))
    end

    @export_log.update_attribute(:job_status, ExportLog::JOB_RUNNING)

    ## if there is something to do, do the deposit
    if @export_log.theses_count > 0


      @exporter.prepare_collection

      log ">>>>>>>> #{@export_log.production_export? ? "PRODUCTION" : "TEST"} MODE <<<<<<<<<<"
      log Thesis.accepted.without_embargo.where("id in (?)", @export_log.theses_ids).to_sql
      theses = Thesis.accepted.without_embargo.where("id in (#{@export_log.theses_ids})")

      log "FOUND: #{theses.size} theses"

      failed_ids = Array.new
      successful_ids = Array.new

      theses.each_with_index do |thesis, index|

        begin
          log "\n==== Depositing #{index + 1} of #{theses.size} ========="
          log "Thesis ID: #{thesis.id}"
          log "Student ID: #{thesis.student.id}"

          entry = thesis_to_atom_entry(thesis)
          files = extract_thesis_filepaths(thesis)

          receipt = @exporter.deposit(entry: entry, files: files, zipped: true, complete: @export_log.complete_thesis?)

          log "Receipt Status: #{receipt.status_code}"
          log "Receipt Message: #{receipt.status_message}"

          # 3) set status of each thesis to publish after it has been published
          if (receipt != nil)
            thesis.publish if @export_log.publish_thesis?
          end

          successful_ids.push(thesis.id)
          @export_log.update_attribute(:successful_count, successful_ids.size)
          @export_log.update_attribute(:successful_ids, successful_ids.join(","))

          log "======================"
        rescue Exception => e
          failed_ids.push(thesis.id)
          error(thesis, e)

          @export_log.update_attribute(:failed_count, failed_ids.size)
          @export_log.update_attribute(:failed_ids, failed_ids.join(","))
        end

        log "\rOf: #{theses.size}. Succeeded: #{successful_ids.size}. Failed: #{failed_ids.size}. "

        sleep(@sleep_interval)
      end



      if failed_ids.size == theses.size
        @export_log.update_attribute(:job_status, ExportLog::JOB_FAILED)
      else
        @export_log.update_attribute(:job_status, ExportLog::JOB_DONE)
      end

    else
      @export_log.update_attribute(:job_status, ExportLog::JOB_DONE)
    end

    ## Run Temp file clean up
    Dir.glob('/tmp/etd-*.zip').each { |f| File.delete(f) }
  end



  ## THESIS MANIPULATION METHODS

  # Go through documents and get the file paths
  def extract_thesis_filepaths(thesis)
    return [] if thesis == nil

    files = []
    thesis.documents.not_deleted.each do |document|
      log "       #{document.file.path}"
      files.push document.file.path
    end

    # plus license file [ NOT REQUIRED ANYMORE]
    # files.push Rails.root.join('lib', 'tasks', 'YorkU_ETDlicense.txt').to_s

    return files
  end



  # Maps thesis to atom entry
  def thesis_to_atom_entry(thesis)
    entry = Atom::Entry.new
    entry.add_dublin_core_extension!("title", thesis.title)
    entry.add_dublin_core_extension!("creator", thesis.author)
    entry.add_dublin_core_extension!("supervisor", thesis.supervisor)


    thesis.loc_subjects.each do |subject|
      entry.add_dublin_core_extension!("subject", subject.name)
    end

    if thesis.keywords != nil
      thesis.keywords.split(",").each do |keyword|
        entry.add_dublin_core_extension!("relationSubjectKeywords", keyword.strip)
      end
    end

    entry.add_dublin_core_extension!("abstract", thesis.abstract)
    entry.add_dublin_core_extension!("language", language_to_iso(thesis.language))
    entry.add_dublin_core_extension!("name", Thesis::DEGREENAME_FULL[thesis.degree_name])
    entry.add_dublin_core_extension!("level", thesis.degree_level)

    entry.add_dublin_core_extension!("discipline", short_program_name(thesis.program))
    entry.add_dublin_core_extension!("issued", Date.current.strftime("%Y-%m-%d"))
    entry.add_dublin_core_extension!("dateCopyrighted", thesis.exam_date.strftime("%Y-%m-%d"))

    entry.add_dublin_core_extension!("type", "Electronic Thesis or Dissertation")
    entry.add_dublin_core_extension!("rights", "Author owns copyright, except where explicitly noted. Please contact the author directly with licensing requests.")

    return entry
  end

  def language_to_iso(language)
    language = "" if language.blank?

    iso = case language.downcase
    when "en", "english", "eng"
       "en"
    when "fr", "french", "fra"
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


  ## UTIL FUNCTIONS
  def settings(production)
    if production
      return {
        username: AppSettings.dspace_live_username, password: AppSettings.dspace_live_password,
        service_document_url: AppSettings.dspace_live_service_document_url,
        collection_uri: AppSettings.dspace_live_collection_uri,
        collection_title: AppSettings.dspace_live_collection_title
      }
    else
      return  {
        username: AppSettings.dspace_test_username, password: AppSettings.dspace_test_password,
        service_document_url: AppSettings.dspace_test_service_document_url,
        collection_uri: AppSettings.dspace_test_collection_uri,
        collection_title: AppSettings.dspace_test_collection_title
      }
    end
  end

  def log(string)
    if @export_log
      o = @export_log.output_full
      @export_log.update_attribute(:output_full, "#{o} \n #{string}")
    end
  end

  def error(thesis, exception)
    exception = Exception.new("No exception raised") if exception == nil

    o = "======= DEPOSIT ERROR =======\n"
    o = o + "TID: #{thesis.id}   UID: #{thesis.student.id} \n" rescue nil
    o = o + "Error: #{exception.message}\n"
    o = o + "--------------------------\n"
    o = o + exception.to_s + "\n"
    o = o + "=============================\n\n"

    @export_log.update_attribute(:output_error, "#{@export_log.output_error} \n #{o}")
  end


end

