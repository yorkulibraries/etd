# frozen_string_literal: true

class GraduateEmailApproval < ApplicationRecord
  belongs_to :student
  belongs_to :approved_by, class_name: 'User'
  belongs_to :replacement_of_connection, class_name: 'GraduateEmailConnection', optional: true
  has_many :challenges, class_name: 'GraduateEmailChallenge', foreign_key: :approval_id
  validates :token_digest, :expires_at, presence: true
  validates :generation, numericality: { only_integer: true, greater_than: 0 }
  validates :normalized_address, presence: true
  validate :canonical_address

  private

  def canonical_address
    normalized = GraduateEmail::Address.normalize(input: normalized_address)
    errors.add(:normalized_address, 'must be one supported individual email address') unless normalized && normalized == normalized_address
  end
end
