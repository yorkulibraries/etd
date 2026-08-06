# frozen_string_literal: true

class Thesis < ApplicationRecord
  attr_accessor :current_user
  after_create :attach_pending_invitations

  ##### VALIDATIONS ######

  validates_presence_of :title, :author, :supervisor, :degree_name, :degree_level, :program, :gem_record_event_id,
                        :exam_date
  validates_presence_of :student_id, message: 'A student must be selected before thesis can be created.'
  validates_presence_of :abstract, if: :updating_by_student?
  validate :certify_content_correct_present, if: :updating_by_student?, on: :submit_for_review
  validate :embargo_step_completed, if: :updating_by_student?, on: :submit_for_review

  def certify_content_correct_present
    if certify_content_correct.blank?
      errors.add(:base, "Please check the ‘I certify that the content is correct’ button to proceed")
    end
  end

  def embargo_step_completed
    return if embargo_step_complete?

    errors.add(:base, 'Complete the embargo step before submitting for review.')
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
  has_many :submission_versions, class_name: 'ThesisSubmissionVersion', dependent: :delete_all
  has_many :embargo_requests, dependent: :destroy
  has_many :committee_members
  has_many :invitations, class_name: 'ThesisInvitation', dependent: :delete_all

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

  enum embargo_selection: {
    undecided: 0,
    not_requested: 1,
    requested: 2
  }, _prefix: :embargo

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
  PROCESS_EMBARGO = 'embargo'
  PROCESS_SUBMIT = 'submit'
  PROCESS_STATUS = 'status'

  ##### SCOPES #####

  scope :open, -> { where('status = ? ', OPEN) }
  scope :under_review, -> { where('status = ? ', UNDER_REVIEW) }
  scope :rejected, -> { where('status = ? ', REJECTED) }
  scope :publication_eligible, lambda { |on: EmbargoRequest.toronto_today|
    blocked_ids = EmbargoRequest.publication_blocking(on: on).select(:thesis_id)
    where(embargoed: false).where.not(id: blocked_ids)
  }
  scope :accepted, -> { where(status: ACCEPTED).publication_eligible }
  scope :published, -> { where(status: PUBLISHED).publication_eligible }
  scope :returned, -> { where('status = ? ', RETURNED) }
  scope :with_embargo, -> { where('embargoed = ? ', true) }
  scope :without_embargo, -> { publication_eligible }
  scope :open_or_returned, -> { where('status = ? OR status = ?', OPEN, RETURNED) }

  def send_invitation!(sent_at: Time.current)
    ThesisInvitation.issue!(student:, thesis: self, sent_at:)
  end

  def current_invitation
    invitations.where.not(accepted_at: nil).order(accepted_at: :desc).first ||
      invitations.order(sent_at: :desc, id: :desc).first
  end

  def invitation_accessible?(at: Time.current)
    return true if invitations.where.not(accepted_at: nil).exists?

    invitation = invitations.order(sent_at: :desc, id: :desc).first
    invitation.nil? || invitation.expires_at >= at
  end

  def accept_invitation!(at: Time.current)
    return true if invitations.where.not(accepted_at: nil).exists?

    invitation = invitations.order(sent_at: :desc, id: :desc).first
    return true unless invitation
    return false if invitation.expires_at < at

    invitation.update!(accepted_at: at)
  end

  def abstract=(text)
    text = '' if text.nil?
    self[:abstract] = text.encode('UTF-8', invalid: :replace, undef: :replace)
  end

  def current_embargo_request
    embargo_requests.where(status: %i[draft submitted]).order(created_at: :desc).first ||
      embargo_requests.order(created_at: :desc).first
  end

  def embargo_step_complete?
    return true if embargo_not_requested?

    completed_statuses = %w[submitted approved declined]
    current_request = current_embargo_request

    embargo_requested? && current_request.present? && completed_statuses.include?(current_request.status)
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

  def attach_pending_invitations
    gem_record = GemRecord.find_by(seqgradevent: gem_record_event_id, sisid: student.sisid)
    return unless gem_record

    ThesisInvitation.where(student:, gem_record:, thesis_id: nil).update_all(thesis_id: id, updated_at: Time.current)
  end
  private :attach_pending_invitations
  
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
  def self.ready_to_publish(on: EmbargoRequest.toronto_today)
    where(status: ACCEPTED).publication_eligible(on: on).where('published_date <= ?', on)
  end

  def publication_blocked?(on: EmbargoRequest.toronto_today)
    embargoed != false || embargo_requests.publication_blocking(on: on).exists?
  end

  def publication_block_reason(on: EmbargoRequest.toronto_today)
    return 'permanent_administrative_embargo' if embargoed != false
    return 'pending_embargo_request' if embargo_requests.submitted.exists?
    return 'approved_embargo_request' if embargo_requests.approved.where('approved_until >= ?', on).exists?

    nil
  end

  def publish(notify: true, additional_recipients: [], custom_message: nil)
    publication = nil

    self.class.transaction do
      locked_thesis = self.class.lock.find_by(id: id)
      next if locked_thesis.nil? || locked_thesis.publication_blocked?

      old_status = locked_thesis.status
      locked_thesis.assign_attributes(
        status: PUBLISHED,
        audit_comment: 'Publishing this thesis. Status changed to published',
        published_at: locked_thesis.published_date
      )
      next unless locked_thesis.save(validate: false)

      publication = { student: locked_thesis.student, old_status: old_status, new_status: locked_thesis.status }
    end

    return false if publication.nil?

    reload
    if notify
      mailer_arguments = [publication[:student], self, publication[:old_status], publication[:new_status]]
      if additional_recipients.present? || custom_message.present?
        mailer_arguments << additional_recipients.dup
        mailer_arguments << custom_message
      end
      StudentMailer.status_change_email(*mailer_arguments).deliver_later
    end
    true
  end

  def self.assigned_to_user(user)
    Thesis.where('assigned_to_id = ?', user.id)
  end

  def has_primary_file?
    return documents.primary.not_deleted.size > 0
  end

  def create_submission_snapshot!(submitted_by)
    with_lock do
      version = submission_versions.create!(
        version_number: ThesisSubmissionVersion.next_version_number_for(self),
        submitted_by: submitted_by,
        submitted_at: Time.current
      )

      documents.not_deleted.order(:id).each do |document|
        unless document.file.path.present? && File.exist?(document.file.path)
          raise CarrierWave::UploadError, "Missing source file for document #{document.id}"
        end

        File.open(document.file.path, 'rb') do |file|
          version.submission_documents.create!(
            source_document: document,
            supplemental: document.supplemental,
            usage: document.usage,
            name: document.name,
            original_filename: File.basename(document.file.path),
            content_type: document.file.file.try(:content_type),
            file_size: File.size(document.file.path),
            file: file
          )
        end
      end

      version
    end
  end

  def documents_for_export
    latest_submission_version = submission_versions.order(version_number: :desc).first
    return documents.not_deleted.where(usage: :thesis) unless latest_submission_version

    latest_submission_version.submission_documents.where(usage: :thesis)
  end

  def degree_name_full
    key = degree_name
    return nil if key.nil? || key.to_s.strip.empty?

    # Build the upcased hash only the first time this method is called
    @upcased_degree_names ||= DEGREENAME_FULL.transform_keys(&:upcase).freeze

    @upcased_degree_names[key.to_s.upcase]
  end
end
