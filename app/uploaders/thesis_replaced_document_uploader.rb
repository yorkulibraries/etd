# frozen_string_literal: true

class ThesisReplacedDocumentUploader < CarrierWave::Uploader::Base
  storage :file

  def store_dir
    "uploads/theses/#{model.thesis_id}/replaced_files/#{model.id}"
  end

  def filename
    model.original_filename.presence || original_filename
  end

  def move_to_store
    true
  end
end
