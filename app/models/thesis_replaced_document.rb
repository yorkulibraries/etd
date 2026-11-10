# frozen_string_literal: true

# A copy of a file staff replaced after the student submitted. Student
# submissions are kept as numbered versions; this keeps what staff overwrote in
# between, so FGS never loses a file the student actually submitted.
class ThesisReplacedDocument < ApplicationRecord
  mount_uploader :file, ThesisReplacedDocumentUploader

  belongs_to :thesis
  belongs_to :source_document, class_name: 'Document', optional: true
  belongs_to :replaced_by, class_name: 'User'

  enum usage: Document.usages

  validates_presence_of :thesis, :replaced_by, :replaced_at, :file, :usage

  # Drafts (open or returned) are the student's work in progress and are not
  # kept, matching submitted versions. Embargo request evidence is staff
  # paperwork, not part of the submission, so it is left out here as well.
  def self.keep_copy?(document)
    !document.embargo_request_document? &&
      [Thesis::OPEN, Thesis::RETURNED].exclude?(document.thesis.status)
  end

  # Builds (without saving) a copy of the document's current file. Assigning
  # the file caches a copy immediately, so it survives the document's upload
  # overwriting the original path.
  def self.build_from(document, replaced_by:)
    path = document.file.path
    raise CarrierWave::UploadError, "Missing source file for document #{document.id}" unless path.present? && File.file?(path)

    File.open(path, 'rb') do |file|
      new(thesis: document.thesis, source_document: document, replaced_by: replaced_by, replaced_at: Time.current,
          supplemental: document.supplemental, usage: document.usage, name: document.name,
          original_filename: File.basename(path), content_type: document.file.file.try(:content_type),
          file_size: File.size(path), file: file)
    end
  end

  def display_name
    name.presence || original_filename.presence || File.basename(file.path.to_s)
  end

  # e.g. Genny_Jon_2024_PhD_replaced_2026-11-09_172905.pdf. The time, to the
  # second, keeps a quick second replacement (wrong file, fixed) apart.
  def download_filename
    extension = File.extname(display_name)
    stem = File.basename(display_name, extension)
    extension = File.extname(original_filename.presence || file.path.to_s) if extension.blank?
    "#{stem}_replaced_#{replaced_at.in_time_zone.strftime('%Y-%m-%d_%H%M%S')}#{extension}"
  end

  def document_type
    return 'supplemental' if usage == 'thesis' && supplemental?
    return 'primary' if usage == 'thesis'
    return 'embargo' if %w[embargo embargo_letter].include?(usage)

    usage
  end
end
