# frozen_string_literal: true

class Thesis < ApplicationRecord
  attr_accessor :current_user

  ##### VALIDATIONS ######

  validates_presence_of :title, :author, :supervisor, :degree_name, :degree_level, :program, :gem_record_event_id,
                        :exam_date
  validates_presence_of :student_id, message: 'A student must be selected before thesis can be created.'
  validates_presence_of :abstract, if: :updating_by_student?
  validate :certify_content_correct_present, if: :updating_by_student?, on: :submit_for_review

  def certify_content_correct_present
    if certify_content_correct.blank?
      errors.add(:base, "Please check the ‘I certify that the content is correct’ button to proceed")
    end
  end

  validates_presence_of :lac_licence_agreement, :yorkspace_licence_agreement, :etd_licence_agreement, if: :updating_by_student?, on: :accept_licences

  
  # validates :abstract, word_count: { maximum: 150 }, if: :masters?
  # validates :abstract, word_count:  { maximum: 350 }, unless: :masters?

  validates :published_date, timeliness: { allow_blank: true }
  validates :exam_date, timeliness: { type: :date }
  validates :title, uniqueness: { scope: [:student_id, :degree_name, :degree_level]}

  ##### RELATIONS ######

  belongs_to :student
  has_many :documents, dependent: :delete_all
  has_many :committee_members

  has_many :thesis_subjectships, dependent: :delete_all
  has_many :loc_subjects, through: :thesis_subjectships
  validates_presence_of :loc_subjects, if: :updating_by_student?

  belongs_to :assigned_to, foreign_key: 'assigned_to_id', class_name: 'User'
  belongs_to :embargoed_by, foreign_key: 'embargoed_by_id', class_name: 'User'

  
  audited associated_with: :student
  has_associated_audits

  paginates_per 20

  accepts_nested_attributes_for :committee_members, allow_destroy: true

  ##### CONSTANTS #######

  OPEN = 'open'
  UNDER_REVIEW = 'under_review'
  RETURNED = 'returned'
  REJECTED = 'rejected'
  ACCEPTED = 'accepted'
  PUBLISHED = 'published'

  STATUSES = [OPEN, UNDER_REVIEW, ACCEPTED, PUBLISHED, RETURNED].freeze
  STATUS_ACTIONS = { OPEN => 'Open', UNDER_REVIEW => 'Under Review', REJECTED => 'Reject', ACCEPTED => 'Accept',
                     PUBLISHED => 'Publish', RETURNED => 'Return' }.freeze

  DEGREENAME = [
    'EMBA', 'IMBA', 'LLM', 'MA', 'MASc', 'MBA', 'Mdes', 'MEd', 'MES', 'MFA', 'MFAc', 'MHRM', 'MPA', 'MPIA', 'MPPAL', 'MSc', 'MScN', 'MSW',
    'MAcc', 'MCI', 'MDEM', 'MBA/JD', 'MES/JD', 'MA/JD', 'PhD'
  ].freeze

  DEGREENAME_FULL = {
    'EMBA' => 'EMBA - Executive Master of Business Administration',
    'IMBA' => 'IMBA - International Master of Business Administration',
    'LLM' => 'LLM - Master of Laws',
    'MA' => 'MA - Master of Arts',
    'MASc' => 'MASc - Master of Applied Science',
    'MBA' => 'MBA - Master of Business Administration',
    'MDes' => 'MDes - Master of Design',
    'MEd' => 'MEd - Master of Education',
    'MES' => 'MES - Master in Environmental Studies',
    'MFA' => 'MFA - Master of Fine Arts',
    'MFAc' => 'MFAc - Master of Financial Accountability',
    'MHRM' => 'MHRM - Master of Human Resources Management',
    'MPA' => 'MPA - Master of Public Administration',
    'MPIA' => "MPIA - Master's in Public and International Affairs",
    'MPPAL' => 'MPPAL - Master of Public Policy, Administration and Law',
    'MSc' => 'MSc - Master of Science',
    'MScN' => 'MScN - Master of Science in Nursing',
    'MSW' => 'MSW - Master of Social Work',
    'MAcc' => 'MAcc - Master of Accounting',
    'MCI' => 'MCI - Master of Conference Interpreting',
    'MDEM' => 'MDEM - Master in Disaster and Emergency Management',
    'MBA/JD' => 'MBA/JD - Master of Business Administration/Juris Doctor',
    'MES/JD' => 'MES/JD - Master in Environmental Studies/Juris Doctor',
    'MA/JD' => 'MA/JD - Master of Arts/Juris Doctor',
    'PhD' => 'PhD - Doctor of Philosophy'
  }.freeze

  LANGUAGE = %w[English French Other].freeze
  MASTERS = "Master's"
  DOCTORAL = 'Doctoral'
  DEGREELEVEL = [MASTERS, DOCTORAL].freeze

  PROCESS_BEGIN = 'begin'
  PROCESS_UPDATE = 'update'
  PROCESS_UPLOAD = 'upload'
  PROCESS_REVIEW = 'review'
  PROCESS_SUBMIT = 'submit'
  PROCESS_STATUS = 'status'

  ##### SCOPES #####

  scope :open, -> { where('status = ? ', OPEN) }
  scope :under_review, -> { where('status = ? ', UNDER_REVIEW) }
  scope :rejected, -> { where('status = ? ', REJECTED) }
  scope :accepted, -> { where('status = ? ', ACCEPTED).where('embargoed = ? ', false) }
  scope :published, -> { where('status = ? ', PUBLISHED).where('embargoed = ? ', false) }
  scope :returned, -> { where('status = ? ', RETURNED) }
  scope :with_embargo, -> { where('embargoed = ? ', true) }
  scope :without_embargo, -> { where('embargoed = ? ', false) }
  scope :open_or_returned, -> { where('status = ? OR status = ?', OPEN, RETURNED) }

  def abstract=(text)
    text = '' if text.nil?
    self[:abstract] = text.encode('UTF-8', invalid: :replace, undef: :replace)
  end

  def assign_degree_name_and_level
    return if program.blank?

    strings = program.split(' ')

    self.degree_name = DEGREENAME.select { |n| n.upcase.include?(strings[1].upcase) }.first
    self.degree_level = (strings[1].upcase == 'PHD' ? Thesis::DOCTORAL : Thesis::MASTERS)
  end

  def display_name
    title
  end

  def masters?
    degree_level == MASTERS
  end

  def updating_by_student?
    # REQUIRES a setting of current_user view current_user instance method

    if @current_user && @current_user.role == User::STUDENT
      true
    else
      false
    end
  end
  
  def update_from_gem_record
    record = GemRecord.find_by_seqgradevent(gem_record_event_id)
    return unless record

    self.title = record.title
    self.gem_record_event_id = record.seqgradevent
    self.supervisor = record.superv
    self.exam_date = record.eventdate
    self.program = record.program
    assign_degree_name_and_level
  end

  ### ASSIGNED_TO methods ###
  def assign_to(user)
    return if user.nil?

    self.assigned_to = user
    save(validate: false)
  end

  def assigned?
    assigned_to != nil
  end

  def unassign
    self.assigned_to = nil
    save(validate: false)
  end

  # Return theses that are ready to publish. Status: ACCEPTED + PublisheDate: Today or before
  def self.ready_to_publish
    Thesis.accepted.where('published_date <= ?', Date.today)
  end

  def publish
    return unless embargoed == false

    self.status = Thesis::PUBLISHED
    self.audit_comment = 'Publishing this thesis. Status changed to published'
    self.published_at = published_date
    ChagingStatusMailer.published(student.email).deliver
    save(validate: false)
  end

  def self.assigned_to_user(user)
    Thesis.where('assigned_to_id = ?', user.id)
  end
end
