# frozen_string_literal: true

class Student < User
  # attr_accessible :name, :email, :username, :sisid, :invitation_sent_at

  belongs_to :created_by, foreign_key: 'created_by_id', class_name: 'User'

  validates_presence_of :sisid
  validates_uniqueness_of :sisid
  validates_length_of :sisid, is: 9
  # validates_format_of :email, with: /.*/

  validate :check_email_addresses

  ALLOWED_TYPE = 'GRAD:STUDENT'

  scope :name_alpha, -> { order('name desc') }
  scope :name_alpha_reverse, -> { order('name asc') }
  scope :most_recent, -> { order('created_at desc') }
  scope :oldest, -> { order('created_at asc') }

  IMMUTABLE_THESIS_FIELDS = %w[title author supervisor committee exam_date program degree_name degree_level embargo
                               published_date id gem_record_event_id status].freeze

  has_many :theses, dependent: :destroy

  audited
  has_associated_audits

  paginates_per 25

  def check_email_addresses
    return if email.nil?

    email.split(/[\s,]+/).each do |address|
      unless address =~ /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\Z/i
        errors.add(:email, "are invalid because of #{address} email")
      end
    end
  end

  def display_name
    name
  end

  ### Finders
  def self.find_by_sisid_or_name(query)
    where('sisid = ? or name LIKE ?', query, "%#{query}%")
  end
end
