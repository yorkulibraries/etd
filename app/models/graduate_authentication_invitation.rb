# frozen_string_literal: true

class GraduateAuthenticationInvitation < ApplicationRecord
  belongs_to :student
  belongs_to :approved_by, class_name: 'User'
  audited associated_with: :student, only: %i[student_id approved_by_id provider expires_at consumed_at revoked_at]

  validates :provider, inclusion: { in: GraduateAuthentication::PROVIDERS }
  validates :token_digest, :expires_at, presence: true
  validates :token_digest, uniqueness: true

  def usable?
    GraduateAuthentication::PROVIDERS.include?(provider) && consumed_at.nil? && revoked_at.nil? && expires_at > Time.current &&
      GraduateAuthentication.active_student?(student) && GraduateAuthentication.staff_authorized?(approved_by)
  end

  def self.for_token(token)
    return unless token.is_a?(String) && token.match?(/\A[A-Za-z0-9_-]{43}\z/)

    find_by(token_digest: Digest::SHA256.hexdigest(token))
  end

  def self.issue!(student:, approved_by:, provider:)
    raise GraduateAuthentication::Rejected unless GraduateAuthentication.active_student?(student) &&
                                                GraduateAuthentication.staff_authorized?(approved_by) &&
                                                GraduateAuthentication.enabled_providers.include?(provider)
    token = SecureRandom.urlsafe_base64(32)
    invitation = nil
    student.with_lock do
      raise GraduateAuthentication::Rejected unless GraduateAuthentication.active_student?(student)

      where(student: student, provider: GraduateAuthentication::PROVIDERS, consumed_at: nil, revoked_at: nil)
        .find_each { |old| old.update!(revoked_at: Time.current) }
      invitation = create!(student: student, approved_by: approved_by, provider: provider,
                           token_digest: Digest::SHA256.hexdigest(token), expires_at: 48.hours.from_now)
    end
    [invitation, token]
  end
end
