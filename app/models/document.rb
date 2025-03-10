# frozen_string_literal: true

class Document < ApplicationRecord
  mount_uploader :file, DocumentUploader
  audited associated_with: :thesis

  ### RELATIONS
  belongs_to :thesis
  belongs_to :user

  #### VALIDATIONS
  validates_presence_of :file, :user, :thesis
  validate :one_primary_file_per_thesis, on: :create
  validate :validate_extension
  validate :validate_usage

  #### SCOPES
  scope :newest, -> { order('created_at desc') }
  scope :oldest,  -> { order('created_at asc') }
  scope :primary, -> { where(usage: :thesis).where('supplemental = ? ', false) }
  scope :supplemental, -> { where(usage: :thesis).where('supplemental = ? ', true) }
  scope :deleted, -> { where('deleted = ?', true) }
  scope :not_deleted, -> { where('deleted = ?', false) }
  
  scope :licence, -> { where(usage: :licence).where('supplemental = ? ', true) }
  scope :embargo, -> { where(usage: [:embargo, :embargo_letter]).where('supplemental = ? ', true) }

  enum usage: %i[thesis embargo embargo_letter licence]

  attribute :usage, default: :thesis
  attribute :supplemental, default: true
  attribute :deleted, default: false

  #### ADDITIONAL METHODS
  def self.primary_thesis_file_extensions
    AppSettings.primary_thesis_file_extensions.split(',').map(&:strip)
  end

  def self.supplemental_thesis_file_extensions
    AppSettings.supplemental_thesis_file_extensions.split(',').map(&:strip)
  end

  def self.licence_file_extensions
    AppSettings.licence_file_extensions.split(',').map(&:strip)
  end

  def self.embargo_file_extensions
    AppSettings.embargo_file_extensions.split(',').map(&:strip)
  end

  def allowed_extensions
    list = Document.primary_thesis_file_extensions

    case document_type
    when 'supplemental'
      list = Document.supplemental_thesis_file_extensions
    when 'licence'
      list = Document.licence_file_extensions
    when 'embargo'
      list = Document.embargo_file_extensions
    else
      list = Document.primary_thesis_file_extensions
    end

    return list
  end

  def destroy
    self.deleted = true
    save(validate: false)
    update_file_sequence
  end

  def display_name
    name
  end

  def primary?
    return !supplemental?
  end

  ### CUSTOM VALIDATIONS
  def one_primary_file_per_thesis
    if primary? && !deleted? && thesis && thesis.has_primary_file?
      errors.add(:file, 'Only one primary file allowed.')
    end
  end

  def file_extension
    return nil unless file.filename.present?
    ext = '.' + file.filename.downcase.split('.').pop
  end

  def validate_extension
    if !valid_extension?
      errors.add(:file, "Extension #{file_extension} is not allowed.")
    end
  end

  def valid_extension?
    return allowed_extensions.include? file_extension
  end

  def validate_usage
    if !valid_usage?
      errors.add(:usage, 'Primary file usage must be "thesis".')
    end
  end

  def valid_usage?
    if primary? && usage != 'thesis'
      return false
    end
    return true
  end

  def document_type
    return 'supplemental' if self.usage == "thesis" && self.supplemental?
    return 'primary' if self.usage == "thesis" && self.primary?
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

    sequence = document_sequence(document_type)
    max = sequence.values.max.nil? ? 0 : sequence.values.max
    number = self.new_record? ? max + 1 : sequence[self.id]

    file_sequence = self.supplemental? ? "_#{self.document_type}_#{number}" : ""

    return "#{full_name}_#{year}_#{deg_name}#{file_sequence}".gsub(/[\s\.\,]/, '_').gsub(/_+/, '_') + ext
  end

  def document_sequence(type)
    docs = []
    docs = thesis.documents.not_deleted.supplemental.order('id') if type == 'supplemental'
    docs = thesis.documents.not_deleted.licence.order('id') if type == 'licence'
    docs = thesis.documents.not_deleted.embargo.order('id') if type == 'embargo'

    s = Hash.new
    docs.each_with_index do |d, i|
      s[d.id] = i + 1
    end
    return s
  end

  def update_file_sequence
    docs = []
    docs = thesis.documents.not_deleted.supplemental if document_type == 'supplemental'
    docs = thesis.documents.not_deleted.embargo if document_type == 'embargo'
    docs = thesis.documents.not_deleted.licence if document_type == 'licence'
    docs.each do |d|
      d.file = File.open(d.file.path)
      d.save! validate: false
      d.name = File.basename(d.file.path)
      d.save! validate: false
    end
  end
end
