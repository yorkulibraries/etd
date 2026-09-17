# frozen_string_literal: true

class DspaceDeposit < ApplicationRecord
  PENDING = 'pending'
  RUNNING = 'running'
  COMPLETE = 'complete'
  FAILED = 'failed'
  REVIEW_REQUIRED = 'review_required'
  LICENSE_STATUSES = [PENDING, RUNNING, COMPLETE, FAILED, REVIEW_REQUIRED].freeze

  UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  belongs_to :thesis
  belongs_to :export_log

  validates :item_uuid, presence: true, uniqueness: true, format: { with: UUID_FORMAT, message: 'is not a UUID' }
  validates :license_status, presence: true, inclusion: { in: LICENSE_STATUSES }
end
