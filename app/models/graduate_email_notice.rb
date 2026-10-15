# frozen_string_literal: true

class GraduateEmailNotice < ApplicationRecord
  belongs_to :old_connection, class_name: 'GraduateEmailConnection'
  belongs_to :replacement_connection, class_name: 'GraduateEmailConnection'
  validates :state, inclusion: { in: %w[queued claimed sent failed] }
end
