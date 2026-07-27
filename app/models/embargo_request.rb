# frozen_string_literal: true

class EmbargoRequest < ApplicationRecord
  TORONTO_TIME_ZONE = 'Eastern Time (US & Canada)'.freeze
  EMAIL_FORMAT = /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i
  REASON_LABELS = {
    'intellectual_property_contract' => 'Approved intellectual-property confidentiality contract',
    'patent_application' => 'Public distribution would invalidate a patent application',
    'publication_contract' => 'Public distribution would invalidate a publication contract',
    'personal_safety' => "Public distribution would pose a risk to the author's personal safety"
  }.freeze

  belongs_to :thesis
  belongs_to :decided_by, class_name: 'User', optional: true
  has_many :documents

  audited associated_with: :thesis,
          only: %i[request_type status reason requested_duration_months
                   submitted_at approved_until decided_at decided_by_id]

  enum request_type: { new_request: 0, extension: 1 }
  enum status: { draft: 0, submitted: 1, approved: 2, declined: 3 }
  enum reason: {
    intellectual_property_contract: 0,
    patent_application: 1,
    publication_contract: 2,
    personal_safety: 3
  }

  validates :request_type, :status, presence: true
  validate :one_open_request_per_thesis, if: -> { draft? || submitted? }

  with_options on: :submission do
    validates :reason, :rationale, :requested_duration_months, :contact_phone, :contact_email,
              :graduate_program_director_name, :graduate_program_director_email,
              :supervisor_name, :supervisor_email, presence: true
    validates :requested_duration_months,
              numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 36 }
    validates :contact_email, :graduate_program_director_email, :supervisor_email,
              format: { with: EMAIL_FORMAT }
    validate :previous_approval_exists_for_extension
    validate :supervisor_letter_present
  end

  scope :publication_blocking, lambda { |on: EmbargoRequest.toronto_today|
    where(status: statuses[:submitted]).or(
      where(status: statuses[:approved]).where('approved_until >= ?', on)
    )
  }

  def self.toronto_today
    Time.find_zone!(TORONTO_TIME_ZONE).today
  end

  def self.reason_options
    REASON_LABELS.map { |value, label| [label, value] }
  end

  def reason_label
    REASON_LABELS.fetch(reason, reason.to_s.humanize)
  end

  def expired?(on: self.class.toronto_today)
    approved? && approved_until.present? && approved_until < on
  end

  def submit_request
    return false unless draft?
    return false unless valid?(:submission)

    update(status: :submitted, submitted_at: Time.current)
  end

  private

  def one_open_request_per_thesis
    open_statuses = [self.class.statuses[:draft], self.class.statuses[:submitted]]
    return if thesis.blank?
    return unless thesis.embargo_requests.where(status: open_statuses).where.not(id: id).exists?

    errors.add(:base, 'This thesis already has an open embargo request.')
  end

  def previous_approval_exists_for_extension
    return unless extension?
    return if thesis.embargo_requests.approved.where.not(id: id).exists?

    errors.add(:request_type, 'requires a previously approved embargo request')
  end

  def supervisor_letter_present
    return if documents.not_deleted.where(usage: Document.usages[:embargo_letter]).exists?

    errors.add(:base, 'Upload a supervisor support letter before submitting the request.')
  end
end
