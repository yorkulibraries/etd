# frozen_string_literal: true

class ThesisSubmissionVersion < ApplicationRecord
  belongs_to :thesis
  belongs_to :submitted_by, class_name: 'User'
  has_many :submission_documents, -> { order(:id) }, class_name: 'ThesisSubmissionDocument', dependent: :delete_all

  validates_presence_of :thesis, :submitted_by, :submitted_at, :version_number
  validates :version_number, uniqueness: { scope: :thesis_id }

  def self.next_version_number_for(thesis)
    where(thesis: thesis).maximum(:version_number).to_i + 1
  end
end
