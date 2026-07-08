# frozen_string_literal: true

class ThesisSubmissionDocumentUploader < CarrierWave::Uploader::Base
  storage :file

  def store_dir
    "uploads/theses/#{model.thesis_id}/submission_versions/#{model.version_number}/files/#{model.id}"
  end

  def filename
    model.stored_filename || original_filename
  end

  def move_to_cache
    true
  end

  def move_to_store
    true
  end
end
