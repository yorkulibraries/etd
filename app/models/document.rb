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

  def self.filename_by_convention(first_name, last_name, middle_name, exam_date, degree_level, filename)
    last_and_first_name = "#{last_name.titleize}_#{first_name.titleize}".gsub(/\s/, '_')
    year_copy = exam_date.year
    grade = degree_level == 'Doctoral' ? 'PhD' : 'Masters'
    year_grade_and_ext = "#{year_copy}_#{grade}#{File.extname(filename)}"

    middle_name.nil? ? "#{last_and_first_name}_#{year_grade_and_ext}"
      : "#{last_and_first_name}_#{middle_name.titleize}_#{year_grade_and_ext}"
  end
end
