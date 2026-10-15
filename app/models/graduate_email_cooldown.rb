# frozen_string_literal: true

class GraduateEmailCooldown < ApplicationRecord
  validates :kind, inclusion: { in: %w[verify_address verify_student verify_ip] }
  validates :key_digest, :blocked_until, presence: true
end
