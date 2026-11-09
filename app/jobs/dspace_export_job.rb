# frozen_string_literal: true

require Rails.root.join('lib/etd/exporter.rb')
require Rails.root.join('lib/etd/dspace_receipt_identifier.rb')
require Rails.root.join('lib/etd/dspace_deposit_package.rb')
require 'ostruct'

class DspaceExportJob < ActiveJob::Base
  attr_accessor :export_log, :sleep_interval, :exporter

  queue_as 'dspace_export'

  # Most bytes kept in output_full and output_error (MySQL TEXT holds 65,535). Older lines are dropped.
  TEXT_LIMIT = 60_000

  def initialize(*args)
    super(*args)

    @export_log = nil
    @sleep_interval = 1
    @exporter = nil
  end

  def perform(export_log_id)
    @export_log = ExportLog.find_by_id(export_log_id)
    return if @export_log.nil?
    # Claim it in one step: skip if it was cancelled before it started, or another worker has it.
    claimed = ExportLog.where(id: @export_log.id, job_status: ExportLog::JOB_OPEN)
                       .update_all(job_status: ExportLog::JOB_RUNNING, job_started_at: Time.current,
                                   updated_at: Time.current)
    return unless claimed == 1

    @export_log.reload
    run_export
  rescue Exception => e # rubocop:disable Lint/RescueException -- never leave an export stuck as running
    fail_export(e) if @export_log
    raise unless e.is_a?(StandardError)
  end

  ## THESIS MANIPULATION METHODS

  def extract_thesis_filepaths(thesis)
    files = ETD::DspaceDepositPackage.files(thesis)
    log "Files: #{files.size}"
    files
  end

  def thesis_to_atom_entry(thesis)
    ETD::DspaceDepositPackage.entry(thesis)
  end

  private

  def run_export
    @counts = { successful: [], failed: [], needs_checking: [] }

    if @export_log.theses_count.to_i.positive?
      @exporter = ETD::Exporter.new(settings) if @exporter.nil?
      @exporter.prepare_collection

      theses = eligible_theses.to_a
      log "FOUND: #{theses.size} theses"
      log 'No captured theses remain publication eligible; skipping DSpace deposit.' if theses.empty?

      theses.each_with_index do |thesis, index|
        # Stop if staff cancelled or cleared this export, or a newer export replaced it.
        unless still_running?
          log 'STOPPED: this export is no longer running, so no more theses were sent.'
          return
        end

        log "Thesis #{thesis.id} (#{index + 1} of #{theses.size})"
        deposit_thesis(thesis)
        sleep(@sleep_interval) if @sleep_interval.to_f.positive?
      end
    end

    finish_export
  ensure
    ## Run Temp file clean up
    Dir.glob('/tmp/etd-*.zip').each { |f| File.delete(f) }
  end

  def deposit_thesis(thesis)
    unless eligible_theses.where(id: thesis.id).exists?
      log "SKIPPED: Thesis ID #{thesis.id} is no longer publication eligible."
      return
    end

    # Build the package before claiming, so a problem here leaves nothing held back.
    entry = thesis_to_atom_entry(thesis)
    files = extract_thesis_filepaths(thesis)

    attempt = ThesisDepositAttempt.claim(thesis:, export_log: @export_log)
    if attempt.nil?
      ThesisDepositAttempt.hold!(thesis:, export_log: @export_log)
      count(:needs_checking, thesis, 'Not sent: an earlier send of this thesis still needs checking in YorkSpace.')
      return
    end

    send_thesis(thesis, attempt, entry, files)
  rescue StandardError => e
    if attempt
      # Something failed after the send started; keep the thesis held back and list it for checking.
      begin
        attempt.needs_checking!("Could not record the result: #{e.message}")
      rescue StandardError
        nil # the claim still holds the thesis back
      end
      count(:needs_checking, thesis, "Could not record the result: #{e.message}") unless counted?(thesis)
    else
      count(:failed, thesis, "Nothing was sent: #{e.message}") unless counted?(thesis)
    end
  end

  def counted?(thesis)
    @counts.values.any? { |ids| ids.include?(thesis.id) }
  end

  # The YorkSpace library raises its own error type, which is not a StandardError; catch it too so one
  # thesis never stops the whole export.
  def send_thesis(thesis, attempt, entry, files)
    begin
      receipt = @exporter.deposit(entry:, files:, zipped: true, complete: true)
    rescue ETD::Exporter::NothingSent => e
      attempt.failed!(e.message)
      return count(:failed, thesis, e.message)
    rescue ETD::Exporter::PartialDeposit => e
      attempt.needs_checking!(e.message, sword_location: e.receipt&.location)
      return count(:needs_checking, thesis, e.message)
    rescue StandardError, Sword2Ruby::Exception => e
      attempt.needs_checking!("The result is unknown, so YorkSpace may have the item: #{e.message}")
      return count(:needs_checking, thesis, e.message)
    end

    if receipt.nil?
      attempt.failed!('Nothing was sent: the thesis details could not be prepared.')
      return count(:failed, thesis, 'Nothing was sent: the thesis details could not be prepared.')
    end

    log "Receipt Status: #{receipt.status_code}"
    attempt.update!(sword_location: receipt.location)
    attempt.update!(licence_handoff: enqueue_license_bundle(receipt, thesis))

    if thesis.publish
      attempt.sent!
      count(:successful, thesis)
    else
      message = 'Deposited to YorkSpace, but the thesis could not be marked published.'
      attempt.needs_checking!(message)
      count(:needs_checking, thesis, message)
    end
  end

  def count(kind, thesis, message = nil)
    @counts[kind].push(thesis.id)
    error(thesis, message) if message
    @export_log.update_columns(successful_count: @counts[:successful].size,
                               successful_ids: @counts[:successful].join(','),
                               failed_count: @counts[:failed].size, failed_ids: @counts[:failed].join(','),
                               needs_checking_count: @counts[:needs_checking].size, updated_at: Time.current)
    nil
  end

  # Also refreshes updated_at, so a long but live export is not treated as stopped.
  def still_running?
    ExportLog.where(id: @export_log.id, job_status: ExportLog::JOB_RUNNING).update_all(updated_at: Time.current) == 1
  end

  def finish_export
    successful = @counts[:successful].size
    attempted = @counts.values.sum(&:size)
    log "Deposited #{successful} of #{attempted} theses. Failed: #{@counts[:failed].size}. " \
        "Need checking: #{@counts[:needs_checking].size}."
    status = attempted.positive? && successful.zero? ? ExportLog::JOB_FAILED : ExportLog::JOB_DONE
    finish(status)
  end

  # Only an export that is still running is finished, so a cancelled one stays cancelled.
  def finish(status)
    ExportLog.where(id: @export_log.id, job_status: ExportLog::JOB_RUNNING)
             .update_all(job_status: status, active_slot: nil, job_completed_at: Time.current, updated_at: Time.current)
    @export_log.reload
  end

  def fail_export(exception)
    error(nil, exception.message)
    finish(ExportLog::JOB_FAILED)
  rescue StandardError
    nil
  end

  ## UTIL FUNCTIONS
  # Hands the item to the licence job. Returns what happened, saved on the send record:
  # queued, not_needed (no REST API URL), no_item_id or error (both shown to staff as needing attention).
  def enqueue_license_bundle(receipt, thesis)
    return 'not_needed' if AppSettings.dspace_rest_api_url.blank?

    item_uuid = ETD::DspaceReceiptIdentifier.item_uuid(receipt)
    unless item_uuid
      log 'LICENSE POST-DEPOSIT SKIPPED: SWORD receipt did not expose a DSpace item UUID'
      return 'no_item_id'
    end

    deposit = DspaceDeposit.find_or_initialize_by(export_log: @export_log, thesis:)
    if deposit.persisted? && deposit.item_uuid != item_uuid
      log "LICENSE POST-DEPOSIT SKIPPED: export already recorded item #{deposit.item_uuid}"
      return 'error'
    end

    deposit.item_uuid = item_uuid
    deposit.sword_location = receipt.location
    deposit.save!
    return 'queued' if [DspaceDeposit::COMPLETE, DspaceDeposit::REVIEW_REQUIRED].include?(deposit.license_status)

    DspaceLicenseBundleJob.perform_later(deposit.id)
    'queued'
  rescue StandardError => e
    log "LICENSE POST-DEPOSIT SETUP ERROR: #{e.message}"
    'error'
  end

  # Each site deposits to the YorkSpace on its own Settings page (etdqa -> ys, live site -> YorkSpace).
  def settings
    {
      username: AppSettings.dspace_live_username, password: AppSettings.dspace_live_password,
      service_document_url: AppSettings.dspace_live_service_document_url,
      collection_uri: AppSettings.dspace_live_collection_uri,
      collection_title: AppSettings.dspace_live_collection_title
    }
  end

  # Writing the log must never stop an export or change a thesis result.
  def log(string)
    append_text(:output_full, string.to_s.strip)
  end

  # One plain line per problem, shown to staff in the export summary.
  def error(thesis, message)
    text = message.presence || 'Unknown error'
    append_text(:output_error, thesis ? "Thesis #{thesis.id}: #{text}" : "Export stopped: #{text}")
  end

  # Appends a line, keeping only the newest TEXT_LIMIT bytes. update_columns: no audit row per line,
  # and updated_at shows the export is alive.
  def append_text(column, line)
    return unless @export_log

    line = ThesisDepositAttempt.storable(line)
    write_text(column, keep_tail([@export_log[column].presence, line].compact.join("\n")))
  rescue StandardError => e
    Rails.logger.warn("DSpace export #{@export_log&.id}: could not write #{column}: #{e.message}")
  end

  def write_text(column, text)
    @export_log.update_columns(column => text, updated_at: Time.current)
  end

  def keep_tail(text)
    return text if text.bytesize <= TEXT_LIMIT

    tail = text.byteslice(-TEXT_LIMIT, TEXT_LIMIT).scrub('')
    tail.sub(/\A[^\n]*\n/, '') # start at a whole line
  end

  def eligible_theses
    Thesis.ready_to_publish
          .where('published_date <= ?', @export_log.published_date)
          .where(id: @export_log.theses_ids.to_s.split(',').map(&:to_i))
  end
end
