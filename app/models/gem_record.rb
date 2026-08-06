# frozen_string_literal: true

class GemRecord < ApplicationRecord
  audited

  validates_presence_of :studentname, :sisid, :emailaddress, :eventtype, :eventdate, :examresult, :title, :program,
                        :superv

  paginates_per 20

  PHD_COMPLETED = 'PhD Dissertation Completion'
  MASTERS_COMPLETED = "Master's Thesis Completion"
  PHD_EXAM = 'PhD Dissertation Exam'
  MASTERS_EXAM = "Master's Thesis Exam"
  ACCEPTED = 'Accepted'

  has_many :committee_members
  has_many :thesis_invitations

  scope :completed, lambda {
                      where('eventtype = ? OR eventtype = ?', GemRecord::PHD_COMPLETED, GemRecord::MASTERS_COMPLETED)
                    }
  scope :exam, -> { where('eventtype = ? OR eventtype = ?', GemRecord::PHD_EXAM, GemRecord::MASTERS_EXAM) }

  def save
    # do nothing
    nil
  end

  def destroy
    # do nothing
    nil
  end

  def display_name
    title
  end

  def current_invitation_for(student)
    student_invitations = thesis_invitations.where(student:)
    student_invitations.where.not(accepted_at: nil).order(accepted_at: :desc).first ||
      student_invitations.order(sent_at: :desc, id: :desc).first
  end

  ### FINDERS ###
  def self.find_by_sisid_or_name(query)
    where('sisid = ? OR studentname LIKE ?', query, "%#{query}%")
  end
end
