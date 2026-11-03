# frozen_string_literal: true

class GraduateEmailConnection < ApplicationRecord
  # A verified connection is historical evidence and the notice recipient.
  # Recovery creates a new row; ordinary model saves cannot redirect history.
  attr_readonly :student_id, :approved_by_id, :normalized_address, :verified_at, :source
  belongs_to :student
  # source 'record': the graduate proved an address on their student record;
  # there is no staff approver. 'staff': FGS approved the address.
  SOURCES = %w[staff record].freeze
  belongs_to :approved_by, class_name: 'User', optional: true
  validates :source, inclusion: { in: SOURCES }
  validate :source_matches_approver
  has_one :active_address, class_name: 'GraduateEmailActiveAddress', foreign_key: :connection_id
  has_many :challenges, class_name: 'GraduateEmailChallenge', foreign_key: :connection_id
  validates :verified_at, presence: true
  validates :normalized_address, presence: true
  validate :canonical_address

  private

  def source_matches_approver
    valid = source == 'record' ? approved_by_id.nil? : approved_by_id.present?
    errors.add(:approved_by, 'must match how this address was approved') unless valid
  end

  def canonical_address
    normalized = GraduateEmail::Address.normalize(input: normalized_address)
    errors.add(:normalized_address, 'must be one supported individual email address') unless normalized && normalized == normalized_address
  end
end
