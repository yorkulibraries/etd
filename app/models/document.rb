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
  validate :supplemental_file_must_be_file_types
  validate :primary_file_must_be_pdf

  #### SCOPES
  scope :newest, -> { order('created_at desc') }
  scope :oldest,  -> { order('created_at asc') }
  scope :primary, -> { where(usage: :thesis).where('supplemental = ? ', false) }
  scope :supplemental, -> { where(usage: :thesis).where('supplemental = ? ', true) }
  scope :deleted, -> { where('deleted = ?', true) }
  scope :not_deleted, -> { where('deleted = ?', false) }
  
  scope :licence, -> { where(usage: :licence) }
  scope :embargo, -> { where(usage: [:embargo, :embargo_letter])}

  enum usage: %i[thesis embargo embargo_letter licence]

  attribute :usage, default: :thesis


  PRIMARY_FILE_EXT = [ '.pdf' ].freeze
  SUPPLEMENTAL_FILE_EXT = ['.pdf', '.doc', '.docx', '.txt', '.html', '.htm', '.odt', '.odp',
    '.ods', '.png', '.tif', '.jpg', '.csv', '.xml', '.avi', '.flac', '.wav', '.mp3', '.mp4', '.mov'].freeze
  EMBARGO_FILE_EXT = ['.pdf', '.txt', '.html', '.htm', '.odt', '.odp', '.ods'].freeze
  LICENCE_FILE_EXT = [ '.pdf' ].freeze

  #### ADDITIONAL METHODS
  def allowed_extensions
    list = PRIMARY_FILE_EXT

    case document_type
    when 'primary'
      list = PRIMARY_FILE_EXT
    when 'supplemental'
      list = SUPPLEMENTAL_FILE_EXT
    when 'licence'
      list = LICENCE_FILE_EXT
    when 'embargo'
      list = EMBARGO_FILE_EXT
    end

    return list
  end

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

  def primary_file_must_be_pdf
    return unless file.filename.present? && !supplemental

    return if file.filename.downcase.end_with?('.pdf')

    errors.add(:file, 'Primary file must be a PDF')
  end

  def supplemental_file_must_be_file_types
    supplemental_file_types = SUPPLEMENTAL_FILE_EXT
    embargo_file_types = EMBARGO_FILE_EXT

    return unless file.filename.present? && supplemental

    if document_type == "licence"
      return if file.filename.downcase.end_with?('.pdf')
    elsif document_type == "supplemental"
      return if supplemental_file_types.include?(File.extname(file.filename.downcase))
    elsif document_type == "embargo"
      return if embargo_file_types.include?(File.extname(file.filename.downcase))
    end

    errors.add(:file, "#{document_type.capitalize} file must be a valid file type")
  end

  def document_type
    return 'supplemental' if self.usage == "thesis" && self.supplemental?
    return 'primary' if self.usage == "thesis" && !self.supplemental?
    return 'embargo' if self.usage == "embargo" || self.usage == "embargo_letter"
    return 'licence' if self.usage == "licence"
  end

  def uploaded_filename(original_filename)
    return original_filename if original_filename.nil? || thesis.nil?

    full_name = thesis.student.name
    year = thesis.exam_date.year
    level = thesis.degree_level
    deg_name = thesis.degree_name
    ext = File.extname(original_filename)


    # count how many supplemental files the thesis already has
    supplemental_count = thesis.documents.supplemental.count
    supplemental_count = supplemental_count + 1 if self.new_record?
    file_sequence =  "_#{self.document_type}_#{supplemental_count}" if document_type == 'supplemental'

    # count how many licence files the thesis already has
    licence_count = thesis.documents.licence.count
    licence_count = licence_count + 1 if self.new_record?
    file_sequence = "_#{self.document_type}_#{licence_count}" if document_type == 'licence'

    # count how many embargo files the thesis already has
    embargo_count = thesis.documents.embargo.count
    embargo_count = embargo_count + 1 if self.new_record?
    file_sequence = "_#{self.document_type}_#{embargo_count}" if document_type == 'embargo'

    return "#{full_name}_#{year}_#{deg_name}#{file_sequence}".gsub(/[\s\.]/, '_') + ext
  end
end
