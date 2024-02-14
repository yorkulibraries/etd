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

  #### SCOPES
  scope :newest, -> { order('created_at desc') }
  scope :oldest,  -> { order('created_at asc') }
  scope :primary, -> { where('supplemental = ? ', false) }
  scope :supplemental, -> { where('supplemental = ? ', true) }
  scope :deleted, -> { where('deleted = ?', true) }
  scope :not_deleted, -> { where('deleted = ?', false) }

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
  validate :filename_naming

  FILENAME_REGEX = /[a-zA-Z]+_[a-zA-Z]+_[a-zA-Z]{1}_\d{4}_(Phd|Masters)\.[a-zA-Z]{3}/
  def filename_naming
    return unless file.filename.present? && !supplemental

    if !FILENAME_REGEX.match?(file.filename) && file.filename.downcase.end_with?('.pdf')
      errors.add(:file,
                 'Lastname_Firstname_MiddleInitial_yearofcopyright_PhdORMasters - this naming convention is needed.')
    elsif !file.filename.downcase.end_with?('.pdf')
      errors.add(:file, 'Primary have to be a PDF')
    end
  end
end
