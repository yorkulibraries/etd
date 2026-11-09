# frozen_string_literal: true

class ExportLog < ApplicationRecord
  audited

  ## CONSTANTS
  JOB_OPEN = 'open'
  JOB_RUNNING = 'running'
  JOB_DONE = 'done'
  JOB_FAILED = 'failed'
  JOB_CANCELLED = 'cancelled'

  JOB_STATUSES = [JOB_OPEN, JOB_RUNNING, JOB_DONE, JOB_FAILED, JOB_CANCELLED].freeze

  # A running export that has written nothing for this long has stopped (for example in a server
  # restart). It no longer blocks new exports; theses it deposited were already marked published.
  STALE_AFTER = 2.hours
  # Interim fix until exports run on a separate background worker: jobs run inside the web server, so a
  # restart can lose a queued export. One that has not started after this long no longer blocks new ones.
  NEVER_STARTED_AFTER = 10.minutes
  # Value of active_slot while an export is waiting or running (empty otherwise). A unique index on
  # the column lets the database refuse a second active export.
  ACTIVE = 1
  BUSY_MESSAGE = 'Another export is still waiting or running. Wait for it to finish, or cancel it, ' \
                 'before starting a new one.'

  ## RELATIONS
  belongs_to :creator, foreign_key: 'user_id', class_name: 'User'
  belongs_to :cancelled_by, foreign_key: 'job_cancelled_by_id', class_name: 'User'
  has_many :dspace_deposits, dependent: :restrict_with_exception
  has_many :thesis_deposit_attempts, dependent: :restrict_with_exception

  ## VALIDATIONS
  validates_presence_of :creator, :job_status, :published_date
  # Checked when staff start an export (save(context: :start)), not for every saved record.
  validate :no_other_active_export, on: :start
  validate :publish_date_not_in_future, on: :start
  validate :theses_ready_to_send, on: :start

  ## SCOPES
  scope :open, -> { where('job_status = ? ', JOB_OPEN) }
  scope :running, -> { where('job_status = ? ', JOB_RUNNING) }
  scope :done, -> { where('job_status = ? ', JOB_DONE) }
  scope :failed, -> { where('job_status = ? ', JOB_FAILED) }
  scope :cancelled, -> { where('job_status = ? ', JOB_CANCELLED) }
  scope :active, lambda {
    where(job_status: JOB_OPEN).where('created_at > ?', NEVER_STARTED_AFTER.ago)
                               .or(where(job_status: JOB_RUNNING).where('updated_at > ?', STALE_AFTER.ago))
  }

  def display_name
    "Export Log - #{job_status} - #{creator.display_name}"
  end

  def stale?
    job_status == JOB_RUNNING && updated_at.present? && updated_at <= STALE_AFTER.ago
  end

  def never_started?
    job_status == JOB_OPEN && created_at.present? && created_at <= NEVER_STARTED_AFTER.ago
  end

  # Frees the slot of exports that never started or stopped making progress, so a new one can start.
  # A lost queued export can no longer start later: the job only claims an export that is still waiting.
  # If such a job is in fact still alive, it sees it is no longer running and stops before its next
  # thesis; the per-thesis send record stops any thesis from being sent twice.
  def self.release_stopped!
    where(job_status: JOB_OPEN).where('created_at <= ?', NEVER_STARTED_AFTER.ago)
                               .update_all(job_status: JOB_FAILED, active_slot: nil, job_completed_at: Time.current,
                                           output_error: 'Export stopped: it never started (for example, the ' \
                                                         'server restarted). Nothing was sent.')
    where(job_status: JOB_RUNNING).where('updated_at <= ?', STALE_AFTER.ago)
                                  .update_all(job_status: JOB_FAILED, active_slot: nil, job_completed_at: Time.current,
                                              output_error: 'Export stopped: it made no progress for two hours.')
  end

  # Cancels only if the export is still waiting, or has stopped making progress, at this moment.
  # One database update decides, so a job starting at the same time cannot also send.
  def cancel!(user)
    changed = ExportLog.where(id:)
                       .where('job_status = ? OR (job_status = ? AND updated_at <= ?)', JOB_OPEN, JOB_RUNNING, STALE_AFTER.ago)
                       .update_all(job_status: JOB_CANCELLED, active_slot: nil, job_cancelled_at: Time.current,
                                   job_cancelled_by_id: user.id, updated_at: Time.current)
    reload
    changed == 1
  end

  # Plain-language result for staff, e.g. "Deposited 3 of 4 theses. Failed: 1."
  def summary
    attempted = successful_count.to_i + failed_count.to_i + needs_checking_count.to_i
    text = "Deposited #{successful_count.to_i} of #{attempted} theses. Failed: #{failed_count.to_i}."
    text += " Need checking in YorkSpace: #{needs_checking_count.to_i}." if needs_checking_count.to_i.positive?
    text
  end

  # Theses that may already be in YorkSpace, or were held back because an earlier send may be.
  def theses_needing_checking
    Thesis.where(id: thesis_deposit_attempts.needing_attention.select(:thesis_id)).order(:id)
  end

  # Why an export stopped before sending anything, in plain words; nil if it did not.
  def stop_reason
    return nil unless job_status == JOB_FAILED

    line = output_error.to_s.lines.map(&:strip).find { |l| l.start_with?('Export stopped: ') }
    return nil if line.nil?

    reason = line.delete_prefix('Export stopped: ')
    if reason.start_with?("Can't Connect To the Service")
      "The website could not connect to YorkSpace (#{reason.delete_prefix("Can't Connect To the Service.").strip}). " \
        'Check the YorkSpace login and address on the Settings page.'
    elsif reason.include?('Collection not found')
      'The website connected to YorkSpace but could not find the collection named on the Settings page.'
    else
      reason
    end
  end

  def licence_summary
    # Theses that reached the licence step (YorkSpace finished their submission).
    sent = thesis_deposit_attempts.where.not(licence_handoff: nil).count
    problems = thesis_deposit_attempts.where(licence_handoff: ThesisDepositAttempt::LICENCE_PROBLEMS).count
    counts = dspace_deposits.group(:license_status).count
    if counts.empty? && problems.zero?
      return 'No theses were fully deposited, so no licences were added.' if sent.zero?
      return 'Licences were not added: the DSpace REST API URL is blank on the Settings page.' if AppSettings.dspace_rest_api_url.blank?

      return 'No licences were needed.'
    end

    text = "Licences added: #{counts[DspaceDeposit::COMPLETE].to_i}. " \
           "Still in progress: #{counts[DspaceDeposit::PENDING].to_i + counts[DspaceDeposit::RUNNING].to_i}. " \
           "Failed: #{counts[DspaceDeposit::FAILED].to_i}. Need review: #{counts[DspaceDeposit::REVIEW_REQUIRED].to_i}."
    if problems.positive?
      text += " Licences need attention for #{problems} #{problems == 1 ? 'thesis' : 'theses'}: " \
              'they could not be queued, so a developer needs to add them.'
    end
    text
  end

  private

  def publish_date_not_in_future
    return if published_date.nil? || published_date <= EmbargoRequest.toronto_today

    errors.add(:base, 'Pick a publish date of today or earlier. Theses are never sent before their publish date.')
  end

  def theses_ready_to_send
    return if theses_count.to_i.positive? || errors.any?

    errors.add(:base, 'No accepted theses are ready to send for this publish date.')
  end

  def no_other_active_export
    return unless ExportLog.active.where.not(id: id).exists?

    errors.add(:base, BUSY_MESSAGE)
  end
end
