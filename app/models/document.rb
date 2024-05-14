# frozen_string_literal: true

class Document < ApplicationRecord
  mount_uploader :file, DocumentUploader
  audited associated_with: :thesis

  ### RELATIONS
  belongs_to :thesis
  belongs_to :user

  #### VALIDATIONS
  validates_presence_of :file, :user, :thesis
  validate :primary_file_presence, on: :create
  validate :filename_naming

  #### SCOPES
  scope :newest, -> { order('created_at desc') }
  scope :oldest,  -> { order('created_at asc') }
  scope :primary, -> { where('supplemental = ? ', false) }
  scope :supplemental, -> { where('supplemental = ? ', true) }
  scope :deleted, -> { where('deleted = ?', true) }
  scope :not_deleted, -> { where('deleted = ?', false) }

  enum usage: %i[thesis embargo embargo_letter licence]

  #### ADDITIONAL METHODS
  def image?
    file.to_s.include?('.gif') or file.to_s.include?('.png') or file.to_s.include?('.jpg')
  end

  def destroy
    self.deleted = true
    save(validate: false)
  end

  def display_name
    name
  end

  ### CUSTOM VALIDATIONS
  def primary_file_presence
    if thesis && (thesis.documents.primary.not_deleted.size.positive? && supplemental? == false && deleted? == false)
      errors.add(:file, 'You can only upload one primary file per thesis')
    end
  end

  def filename_naming
    return unless file.filename.present? && !supplemental

    return if file.filename.downcase.end_with?('.pdf')

    errors.add(:file, 'Primary have to be a PDF')
  end

  def self.filename_by_convention(name, exam_date, degree_name, degree_level, original_filename, is_supplemental, usage)
    full_name = "#{name.titleize}".gsub(/\s/, '_')
    year_copy = exam_date.year
    level = degree_level == 'Doctoral' ? 'PhD' : 'Masters'
    deg_name = degree_name.gsub(/\s/, '_')
    year_degree_and_ext = "#{year_copy}_#{deg_name}_#{level}"
    usage == nil ? usage_caps = '' : usage_caps = usage.upcase
    # sequence = self.thesis.documents.count

    # upload_type = self.supplemental == "Supplemental" ? "Supplemental" : "Primary"
    if is_supplemental 
      upload_type = "Supplemental"
      return "#{full_name}_#{year_degree_and_ext}_#{usage_caps}_#{upload_type}_#{original_filename}"
    elsif self.primary
      upload_type = "Primary"
      return "#{full_name}_#{year_degree_and_ext}_#{usage_caps}_#{upload_type}#{File.extname(original_filename)}"
    else
      return "#{full_name}_#{year_degree_and_ext}_#{usage_caps}_#{original_filename}"
    end
  end

end
