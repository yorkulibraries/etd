# frozen_string_literal: true

class GraduateEmailAuditEvent < ApplicationRecord
  belongs_to :student, optional: true
  belongs_to :actor, class_name: 'User', optional: true
  belongs_to :connection, class_name: 'GraduateEmailConnection', optional: true
  belongs_to :approval, class_name: 'GraduateEmailApproval', optional: true
  belongs_to :challenge, class_name: 'GraduateEmailChallenge', optional: true
  validates :event, :outcome, presence: true
  validates :generation, numericality: { only_integer: true, greater_than: 0 }
end
