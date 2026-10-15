# frozen_string_literal: true

class GraduateEmailActiveAddress < ApplicationRecord
  belongs_to :student
  belongs_to :connection, class_name: 'GraduateEmailConnection'
  validates :normalized_address, presence: true
  validate :canonical_address

  private

  def canonical_address
    normalized = GraduateEmail::Address.normalize(input: normalized_address)
    errors.add(:normalized_address, 'must be one supported individual email address') unless normalized && normalized == normalized_address
  end
end
