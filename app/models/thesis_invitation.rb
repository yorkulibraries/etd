# frozen_string_literal: true

class ThesisInvitation < ApplicationRecord
  belongs_to :student
  belongs_to :gem_record, optional: true
  belongs_to :thesis, optional: true

  validates :sent_at, :expires_at, :upload_expires_at, presence: true
  validate :target_present
  before_validation :set_default_upload_expiry

  def self.issue!(student:, gem_record: nil, thesis: nil, sent_at: Time.current)
    create!(
      student:,
      gem_record:,
      thesis:,
      sent_at:,
      expires_at: toronto_deadline(sent_at, AppSettings.invitation_validity_days),
      upload_expires_at: toronto_deadline(sent_at, AppSettings.upload_validity_days)
    )
  end

  def self.toronto_deadline(sent_at, days)
    toronto_time = sent_at.in_time_zone('Eastern Time (US & Canada)')
    expiry_date = toronto_time.to_date + days.to_i
    toronto_time.time_zone.local(expiry_date.year, expiry_date.month, expiry_date.day).end_of_day
  end

  def expiry_label
    self.class.toronto_label(expires_at)
  end

  def upload_expiry_label
    self.class.toronto_label(upload_expires_at)
  end

  def self.toronto_label(time)
    time.in_time_zone('Eastern Time (US & Canada)').strftime('%B %-d, %Y at %-I:%M %p %Z')
  end

  private

  def set_default_upload_expiry
    self.upload_expires_at ||= expires_at
  end

  def target_present
    errors.add(:base, 'An invitation must belong to an ETD') unless gem_record || thesis
  end
end
