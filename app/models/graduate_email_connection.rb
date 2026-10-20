# frozen_string_literal: true

class GraduateEmailConnection < ApplicationRecord
  # A verified connection is historical evidence and the notice recipient.
  # Recovery creates a new row; ordinary model saves cannot redirect history.
  attr_readonly :student_id, :approved_by_id, :normalized_address, :verified_at
  belongs_to :student
  belongs_to :approved_by, class_name: 'User'
  has_one :active_address, class_name: 'GraduateEmailActiveAddress', foreign_key: :connection_id
  has_many :challenges, class_name: 'GraduateEmailChallenge', foreign_key: :connection_id
  validates :verified_at, presence: true
  validates :normalized_address, presence: true
  validate :canonical_address

  private

  def canonical_address
    normalized = GraduateEmail::Address.normalize(input: normalized_address)
    errors.add(:normalized_address, 'must be one supported individual email address') unless normalized && normalized == normalized_address
  end
end
