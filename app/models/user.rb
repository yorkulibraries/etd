# frozen_string_literal: true

class User < ApplicationRecord
  audited
  devise :registerable

  before_save :default_values

  validates_presence_of :username, :name, :email, :role
  validates_uniqueness_of :username, :email
  validates_format_of :username, with: /^[-\w._]+$/i, multiline: true, allow_blank: false,
                                 message: 'should only contain letters, numbers, or .-_'
  validates_format_of :email, with: /^[-a-z0-9_+.]+@([-a-z0-9]+\.)+[a-z0-9]{2,4}$/i, multiline: true,
                              message: 'Email must follow address@domain format', unless: :is_student?

  belongs_to :created_by, foreign_key: 'created_by_id', class_name: 'User'

  ADMIN = 'admin'
  MANAGER = 'manager'
  STAFF = 'staff'
  STUDENT = 'student'
  ROLE_NAMES = [ADMIN, MANAGER, STAFF, STUDENT].freeze
  ROLES = [[ADMIN.titleize, ADMIN], [MANAGER.titleize, MANAGER], [STAFF.titleize, STAFF]].freeze

  scope :active, -> { where(blocked: false).order('users.name asc') }
  scope :blocked, -> { where(blocked: true).order('users.name asc') }
  scope :not_students, -> { where("users.role <> '#{STUDENT}'") }
  scope :admins, -> { where(role: ADMIN) }

  def active?
    !blocked?
  end

  def block
    update_attribute(:blocked, true)
  end

  def unblock
    update_attribute(:blocked, false)
  end

  def created_by_name
    if created_by.nil?
      name
    else
      created_by.name
    end
  end

  def self.find_active_user(criterion)
    return nil if criterion.blank?

    if criterion =~ /^[0-9]+$/
      Student.active.find_by_sisid(criterion)
    else
      User.active.not_students.find_by_username(criterion)
    end
  end

  def display_name
    name
  end

  private

  def default_values
    self.role ||= STAFF
  end

  def is_student?
    is_a? Student
  end
end
