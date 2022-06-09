class GemRecord < ApplicationRecord
  audited

  #attr_accessible :studentname, :sisid, :emailaddress, :eventtype, :eventdate, :examresult, :title, :program, :superv

  validates_presence_of :studentname, :sisid, :emailaddress, :eventtype, :eventdate, :examresult, :title, :program, :superv

  paginates_per 20

  PHD_COMPLETED = "PhD Dissertation Completion"
  MASTERS_COMPLETED = "Master's Thesis Completion"
  PHD_EXAM = "PhD Dissertation Exam"
  MASTERS_EXAM = "Master's Thesis Exam"
  ACCEPTED = "Accepted"

  scope :completed, -> { where("eventtype = ? OR eventtype = ?", GemRecord::PHD_COMPLETED, GemRecord::MASTERS_COMPLETED) }
  scope :exam, -> { where("eventtype = ? OR eventtype = ?", GemRecord::PHD_EXAM, GemRecord::MASTERS_EXAM) }


  def save
    # do nothing
    return
  end

  def destroy
    # do nothing
    return
  end

  def display_name
    title
  end



  ### FINDERS ###
  def self.find_by_sisid_or_name(query)
    where("sisid = ? OR studentname LIKE ? ", query, "%#{query}%")
  end

end
