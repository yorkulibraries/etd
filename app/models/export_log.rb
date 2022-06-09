class ExportLog < ApplicationRecord

  audited

  ## CONSTANTS
  JOB_OPEN = "open"
  JOB_RUNNING = "running"
  JOB_DONE = "done"
  JOB_FAILED = "failed"
  JOB_CANCELLED = "cancelled"

  JOB_STATUSES = [JOB_OPEN, JOB_RUNNING, JOB_DONE, JOB_FAILED, JOB_CANCELLED]

  ## RELATIONS
  belongs_to :creator, foreign_key: "user_id", class_name: "User"
  belongs_to :cancelled_by, foreign_key: "job_cancelled_by_id", class_name: "User"

  ## VALIDATIONS
  validates_presence_of :creator, :job_status, :published_date

  ## SCOPES
  scope :open, -> { where("job_status = ? ", JOB_OPEN) }
  scope :running, -> { where("job_status = ? ", JOB_RUNNING) }
  scope :done, -> { where("job_status = ? ", JOB_DONE) }
  scope :failed, -> { where("job_status = ? ", JOB_FAILED) }
  scope :cancelled, -> { where("job_status = ? ", JOB_CANCELLED) }

  def display_name
    "Export Log - #{job_status} - #{creator.display_name}"
  end
end
