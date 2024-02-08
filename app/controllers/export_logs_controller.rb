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
    ids = Thesis.accepted.where(published_date: @export_log.published_date).ids
    @export_log.theses_count = ids.size
    @export_log.theses_ids = ids.join(',')

    @export_logs = ExportLog.open

    if @export_log.save
      ## Create the Job
      DspaceExportJob.perform_later(@export_log.id)

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
    notice = "Export job was not cancelled because it's already running"

    if @export_log.job_status == ExportLog::JOB_OPEN
      @export_log.with_lock do
        @export_log.job_status = ExportLog::JOB_CANCELLED
        @export_log.job_cancelled_at = Date.today
        @export_log.cancelled_by = current_user
        @export_log.save!(validate: false)
        notice = 'Export job was cancelled'
      end
    end

    respond_to do |format|
      format.html { redirect_to export_logs_path, notice: }
      format.js
    end
  end

  private

  def export_log_params
    params.require(:export_log).permit(:published_date, :complete_thesis, :publish_thesis, :production_export)
  end

  def load_export_log
    @export_log = ExportLog.find(params[:id])
  end
end
