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

  delegate :thesis_id, :version_number, :submitted_at, to: :submission_version

  def display_name
    name.presence || original_filename.presence || File.basename(file_url)
  end

  # Every submitted version keeps the student's original file name, so once
  # staff download several versions they would otherwise be indistinguishable.
  # Label the download with its version and submission date instead, e.g.
  # Genny_Jon_2024_PhD_v1_submitted_2026-10-27.pdf.
  def download_filename
    name = display_name
    extension = File.extname(name)
    stem = File.basename(name, extension)
    # Older records can carry a display name without an extension; fall back
    # to the stored file's so the download still opens in the right program.
    extension = File.extname(original_filename.presence || file.path.to_s) if extension.blank?
    "#{stem}_v#{version_number}_submitted_#{submitted_at.in_time_zone.to_date.iso8601}#{extension}"
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
