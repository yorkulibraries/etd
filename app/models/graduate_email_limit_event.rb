# frozen_string_literal: true

class GraduateEmailLimitEvent < ApplicationRecord
  KINDS = %w[send_address request_ip verify_address verify_student verify_ip admission_send admission_verify].freeze
  validates :kind, inclusion: { in: KINDS }
  validates :key_digest, :occurred_at, presence: true
end
