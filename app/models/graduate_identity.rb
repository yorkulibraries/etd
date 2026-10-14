# frozen_string_literal: true

class GraduateIdentity < ApplicationRecord
  belongs_to :student
  belongs_to :linked_by, class_name: 'User', optional: true
  has_many :graduate_sessions, dependent: :delete_all
  audited associated_with: :student, only: %i[student_id provider linked_by_id link_method]

  validates :provider, inclusion: { in: GraduateAuthentication::PROVIDERS }
  validates :uid, presence: true, length: { maximum: 191 }, uniqueness: { scope: :provider }
  validates :provider, uniqueness: { scope: :student_id }
  validate :student_role

  private

  def student_role
    errors.add(:student, 'must be an active student') unless GraduateAuthentication.active_student?(student)
  end
end
