# frozen_string_literal: true

class ThesisInvitation < ApplicationRecord
  belongs_to :student
  belongs_to :gem_record, optional: true
  belongs_to :thesis, optional: true

  validates :sent_at, :expires_at, presence: true
  validate :target_present

  def self.issue!(student:, gem_record: nil, thesis: nil, sent_at: Time.current)
    toronto_time = sent_at.in_time_zone('Eastern Time (US & Canada)')
    expiry_date = toronto_time.to_date + AppSettings.invitation_validity_days.to_i
    expires_at = toronto_time.time_zone.local(expiry_date.year, expiry_date.month, expiry_date.day).end_of_day

    create!(student:, gem_record:, thesis:, sent_at:, expires_at:)
  end

  private

  def target_present
    errors.add(:base, 'An invitation must belong to an ETD') unless gem_record || thesis
  end
end
