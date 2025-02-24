# frozen_string_literal: true

class CommitteeMember < ApplicationRecord
  ## CONSTANTS

  CHAIR = 'Chair'
  COMMITTEE_MEMBER = 'Committee Member'
  OUTSIDE_MEMBER = 'Outside Member'
  DEANS_REPRESENTATIVE = "Dean's Representative"
  EXTERNAL_EXAMINER = 'External Examiner'

  ROLES = [CHAIR, COMMITTEE_MEMBER, OUTSIDE_MEMBER, DEANS_REPRESENTATIVE, EXTERNAL_EXAMINER].freeze

  ## RELATIONS ##
  belongs_to :thesis
  belongs_to :gem_record

  ## VALIDATIONS ##
  validates_presence_of :first_name
  validates_presence_of :last_name
  # validates_presence_of :thesis
  validates_presence_of :role

  ## SCOPES ##
  scope :unique_names, -> { select('DISTINCT(full_name)').order('full_name asc') }

  ## Audited ##
  audited associated_with: :thesis

  # DISPLAY NAME FOR AUDITABLE
  def display_name
    name
  end

  def name
    if !last_name.nil? && !first_name.nil?
      return "#{last_name}, #{first_name}"
    end
    return full_name
  end
end
