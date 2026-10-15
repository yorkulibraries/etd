# frozen_string_literal: true

class GraduateEmailChallenge < ApplicationRecord
  belongs_to :student, optional: true
  belongs_to :approval, class_name: 'GraduateEmailApproval', optional: true
  belongs_to :connection, class_name: 'GraduateEmailConnection', optional: true
  validates :public_id, :browser_digest, :expires_at, presence: true
  validates :purpose, inclusion: { in: %w[enroll login noop] }
  validates :state, inclusion: { in: %w[queued noop claimed sending sent failed superseded revoked consumed expired] }
  validates :generation, numericality: { only_integer: true, greater_than: 0 }
  validates :failed_attempts, numericality: { only_integer: true, in: 0..5 }
end
