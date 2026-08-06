# frozen_string_literal: true

class ThesisSubmissionDocument < ApplicationRecord
  mount_uploader :file, ThesisSubmissionDocumentUploader

  belongs_to :submission_version, class_name: 'ThesisSubmissionVersion',
                                  foreign_key: 'thesis_submission_version_id'
  belongs_to :source_document, class_name: 'Document', optional: true

  enum usage: Document.usages

  scope :primary, -> { where(usage: :thesis).where('supplemental = ? ', false) }
  scope :supplemental, -> { where(usage: :thesis).where('supplemental = ? ', true) }

  validates_presence_of :submission_version, :file, :usage

  delegate :thesis_id, :version_number, to: :submission_version

  def display_name
    name.presence || original_filename.presence || File.basename(file_url)
  end

  def stored_filename
    original_filename.presence || name.presence
  end

  def document_type
    return 'supplemental' if usage == 'thesis' && supplemental?
    return 'primary' if usage == 'thesis' && !supplemental?
    return 'embargo' if usage == 'embargo' || usage == 'embargo_letter'
    return 'licence' if usage == 'licence'
  end
end
