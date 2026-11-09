# frozen_string_literal: true

class ExportLogsController < ApplicationController
  authorize_resource

  before_action :load_export_log, except: %i[index create new]

  def index
    @status = params[:which]
    case @status
    when ExportLog::JOB_RUNNING
      @export_logs = ExportLog.running
    when ExportLog::JOB_FAILED
      @export_logs = ExportLog.failed
    when ExportLog::JOB_DONE
      @export_logs = ExportLog.done
    when ExportLog::JOB_CANCELLED
      @export_logs = ExportLog.cancelled
    else
      @export_logs = ExportLog.open
      @status = ExportLog::JOB_OPEN
    end
  end

  def show; end

  def new
    @export_log = ExportLog.new
  end

  def edit; end

  def create
    @export_log = ExportLog.new(export_log_params)
    @export_log.creator = current_user
    @export_log.audit_comment = 'Adding a new Export Job'
    @export_log.job_status = ExportLog::JOB_OPEN
    # Like the server script: always finish the YorkSpace submission and mark theses published,
    # so a second export of the same date cannot send them again.
    @export_log.complete_thesis = true
    @export_log.publish_thesis = true
    # Like the server script: every accepted thesis whose publish date is on or before the chosen
    # date (which must be today or earlier), so theses left over from earlier dates are not missed.
    ids = Thesis.ready_to_publish.where('published_date <= ?', @export_log.published_date).ids
    @export_log.theses_count = ids.size
    @export_log.theses_ids = ids.join(',')
    @export_log.active_slot = ExportLog::ACTIVE

    ExportLog.release_stopped!
    if start_export
      ## Create the Job
      DspaceExportJob.perform_later(@export_log.id)
      # The job may already have moved it to Running, so refresh the list with both tabs' rows.
      @status = ExportLog::JOB_OPEN
      @export_logs = ExportLog.where(id: @export_log.id).or(ExportLog.open)

      respond_to do |format|
        format.html { redirect_to export_logs_path, notice: 'Submitted an Export Job' }
        format.js
      end
    else
      respond_to do |format|
        format.html { render action: 'new' }
        format.js
      end
    end
  end

  def update
    respond_to do |format|
      format.html { redirect_to export_logs_path, notice: "Export can't be updated" }
      format.js
    end
  end

  def destroy
    # A running export can only be cleared once it has stopped making progress (see ExportLog#stale?).
    notice = if @export_log.cancel!(current_user)
               'Export job was cancelled'
             else
               "Export job was not cancelled because it's already running"
             end

    respond_to do |format|
      format.html { redirect_to export_logs_path, notice: }
      format.js
    end
  end

  private

  # Saves the export, or explains why not. The database refuses a second active export even when two
  # requests pass the friendly check at the same moment.
  def start_export
    @export_log.save(context: :start)
  rescue ActiveRecord::RecordNotUnique
    @export_log.errors.add(:base, ExportLog::BUSY_MESSAGE)
    false
  end

  def export_log_params
    params.require(:export_log).permit(:published_date)
  end

  def load_export_log
    @export_log = ExportLog.find(params[:id])
  end
end
