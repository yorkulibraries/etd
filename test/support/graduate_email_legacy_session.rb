# frozen_string_literal: true
require 'digest'
require 'securerandom'

class GraduateEmailLegacySession < ApplicationRecord
  self.table_name = 'graduate_sessions'
  LIFETIME = 12.hours
  belongs_to :graduate_identity

  def self.issue!(identity)
    raise GraduateAuthentication::Rejected unless GraduateAuthentication::PROVIDERS.include?(identity.provider)

    token = SecureRandom.hex(32)
    create!(graduate_identity: identity, token_digest: Digest::SHA256.hexdigest(token),
            expires_at: LIFETIME.from_now)
    token
  end

end
