# frozen_string_literal: true

require 'digest'
require 'securerandom'

class GraduateSession < ApplicationRecord
  LIFETIME = 12.hours
  TOKEN_FORMAT = /\A[0-9a-f]{64}\z/

  belongs_to :graduate_identity

  validates :token_digest, presence: true, format: { with: TOKEN_FORMAT }, uniqueness: true
  validates :expires_at, presence: true

  def self.marked?(authentication_session)
    authentication_session[:auth_source] == 'graduate_oauth' ||
      authentication_session['auth_source'] == 'graduate_oauth' ||
      %w[graduate_identity_id graduate_session_token].any? do |key|
        authentication_session.key?(key) || authentication_session.key?(key.to_sym)
      end
  end

  def self.issue!(identity)
    raise GraduateAuthentication::Rejected unless GraduateAuthentication::PROVIDERS.include?(identity.provider)

    token = SecureRandom.hex(32)
    create!(graduate_identity: identity, token_digest: Digest::SHA256.hexdigest(token),
            expires_at: LIFETIME.from_now)
    token
  end

  def self.valid_for?(token, identity_id:, student_id:)
    return false unless valid_token?(token) && identity_id.present? && student_id.present?

    joins(:graduate_identity)
      .where(token_digest: Digest::SHA256.hexdigest(token), graduate_identity_id: identity_id, revoked_at: nil)
      .where('graduate_sessions.expires_at > ?', Time.current)
      .where(graduate_identities: { student_id: student_id, provider: GraduateAuthentication::PROVIDERS }).exists?
  end

  def self.revoke(token)
    return unless valid_token?(token)

    where(token_digest: Digest::SHA256.hexdigest(token), revoked_at: nil).update_all(revoked_at: Time.current)
  end

  def self.revoke_for_student(student_id)
    identities = GraduateIdentity.where(student_id: student_id).select(:id)
    where(graduate_identity_id: identities, revoked_at: nil).update_all(revoked_at: Time.current)
  end

  def self.valid_token?(token)
    token.is_a?(String) && TOKEN_FORMAT.match?(token)
  end
  private_class_method :valid_token?
end
