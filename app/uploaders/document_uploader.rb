# frozen_string_literal: true

class DocumentUploader < CarrierWave::Uploader::Base
  # Include RMagick or MiniMagick support:
  # include CarrierWave::RMagick
  # include CarrierWave::MiniMagick

  # Include the Sprockets helpers for Rails 3.1+ asset pipeline compatibility:
  # include Sprockets::Helpers::RailsHelper
  # include Sprockets::Helpers::IsolatedHelper

  # Choose what kind of storage to use for this uploader:
  storage :file
  # storage :fog

  # Override the directory where uploaded files will be stored.
  # This is a sensible default for uploaders that are meant to be mounted:
  def store_dir
    "uploads/theses/#{model.thesis.id}/files/#{model.id}"
  end

  # Add a white list of extensions which are allowed to be uploaded.
  # For images you might use something like this:
  # def extension_white_list
  #   %w(jpg jpeg gif png)
  # end

  # Override the filename of the uploaded files:
  # Avoid using model.id or version_name here, see uploader/store.rb for details.
  def filename
    return original_filename unless model.user.present? && !model.user.name.nil?
    return "#{original_filename}" if model.usage != "thesis"
    # return "#{model.usage.upcase}_#{original_filename}" if model.usage != "thesis"

    ## Therefore, thesis upload
    Document.filename_by_convention(model.user.name, model.thesis.exam_date, model.thesis.degree_name, model.thesis.degree_level, original_filename, model.supplemental, model.usage)
  end

  def move_to_cache
    true
  end

  def move_to_store
    true
  end
end
