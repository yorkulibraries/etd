# frozen_string_literal: true
require 'digest'
require 'securerandom'

class GraduateSession < ApplicationRecord
  LIFETIME = 12.hours
  TOKEN_FORMAT = /\A[0-9a-f]{64}\z/
  MARKERS = %w[graduate_identity_id graduate_email_connection_id graduate_email_generation graduate_session_token].freeze

  belongs_to :graduate_identity, optional: true
  belongs_to :graduate_email_connection, optional: true
  validates :token_digest, presence: true, format: { with: TOKEN_FORMAT }, uniqueness: true
  validates :expires_at, presence: true

  def self.marked?(state)
    %w[graduate_oauth graduate_email].any? { |source| [state[:auth_source], state['auth_source']].include?(source) } ||
      MARKERS.any? { |key| state.key?(key) || state.key?(key.to_sym) }
  end

  def self.valid_markers_for?(state, student)
    return false unless GraduateAuthentication.active_student?(student)
    # Rails sessions canonicalize keys; ordinary hashes must not supply duplicate
    # symbol/string variants, even when their values happen to agree.
    keys = MARKERS + %w[auth_source user_id return_to_user_id]
    return false if keys.any? { |key| state.keys.include?(key) && state.keys.include?(key.to_sym) }

    read = ->(key) { state.key?(key) ? state[key] : state[key.to_sym] }
    present = ->(key) { state.key?(key) || state.key?(key.to_sym) }
    return false unless read.call('user_id') == student.id && read.call('return_to_user_id').blank?

    case read.call('auth_source')
    when 'graduate_oauth'
      return false if %w[graduate_email_connection_id graduate_email_generation].any? { |key| present.call(key) }
      identity_id = read.call('graduate_identity_id')
      return false unless positive_integer?(identity_id)
      valid_for?(read.call('graduate_session_token'), identity_id: identity_id, student_id: student.id)
    when 'graduate_email'
      return false if present.call('graduate_identity_id')
      connection_id, generation = read.call('graduate_email_connection_id'), read.call('graduate_email_generation')
      return false unless positive_integer?(connection_id) && positive_integer?(generation)
      valid_for?(read.call('graduate_session_token'), email_connection_id: connection_id,
        generation: generation, method: 'email', student_id: student.id)
    else
      false
    end
  end

  def self.issue!(identity)
    raise GraduateAuthentication::Rejected unless identity&.persisted? && GraduateAuthentication::PROVIDERS.include?(identity.provider)

    # A real write first also serializes SQLite; SELECT FOR UPDATE alone cannot.
    Student.transaction do
      write_student_lock!(identity.student_id)
      student = Student.lock.find_by(id: identity.student_id)
      current = GraduateIdentity.find_by(id: identity.id)
      raise GraduateAuthentication::Rejected unless GraduateAuthentication.active_student?(student) &&
        current && current.student_id == student.id && GraduateAuthentication::PROVIDERS.include?(current.provider)

      insert_token!(graduate_identity_id: current.id)
    end
  end

  def self.issue_email!(connection:, generation:)
    control = GraduateEmail::Control.locked_state!
    raise GraduateAuthentication::Rejected unless GraduateEmail.configured? && control.enabled &&
      positive_integer?(generation) && control.generation == generation && connection&.persisted?

    # The caller's control transaction owns these locks until commit. Reload all
    # authoritative values, never trust the supplied connection instance.
    student_id = GraduateEmailConnection.where(id: connection.id).pick(:student_id)
    student = Student.lock.find_by(id: student_id)
    raise GraduateAuthentication::Rejected unless GraduateAuthentication.active_student?(student)

    current = GraduateEmailConnection.lock.find_by(id: connection.id)
    mapping = GraduateEmailActiveAddress.lock.find_by(student_id: student.id)
    raise GraduateAuthentication::Rejected unless current_email_mapping?(current, mapping, student.id)

    insert_token!(graduate_email_connection_id: current.id, authentication_method: 'email', email_generation: generation)
  end

  def self.valid_for?(token, identity_id: nil, email_connection_id: nil, method: 'google', generation: nil, student_id:)
    return false unless valid_token?(token) && positive_integer?(student_id)

    if method == 'google'
      return false unless positive_integer?(identity_id) && email_connection_id.nil? && generation.nil?

      records = joins(graduate_identity: :student)
        .where(token_digest: Digest::SHA256.hexdigest(token), graduate_identity_id: identity_id, revoked_at: nil)
        .where('graduate_sessions.expires_at > ?', Time.current)
        .where(graduate_identities: { student_id: student_id, provider: GraduateAuthentication::PROVIDERS })
        .where(users: {blocked: false, role: User::STUDENT, type: 'Student'})
      method_columns = %w[authentication_method graduate_email_connection_id email_generation] & column_names
      # Support boot before migration and after full rollback. A partial schema
      # is never interpreted as legacy; migrated rows always require exact method.
      return records.exists? if method_columns.empty?
      return false unless method_columns.length == 3

      records.where(authentication_method: 'google', graduate_email_connection_id: nil, email_generation: nil).exists?
    elsif method == 'email'
      return false unless identity_id.nil? && positive_integer?(email_connection_id) && positive_integer?(generation) && GraduateEmail.configured?

      GraduateEmail::Control.synchronize do |control|
        next false unless control.enabled && control.generation == generation

        student = Student.lock.find_by(id: student_id)
        next false unless GraduateAuthentication.active_student?(student)

        connection = GraduateEmailConnection.lock.find_by(id: email_connection_id)
        mapping = GraduateEmailActiveAddress.lock.find_by(student_id: student_id)
        next false unless current_email_mapping?(connection, mapping, student_id)

        where(authentication_method: 'email', token_digest: Digest::SHA256.hexdigest(token),
          graduate_identity_id: nil, graduate_email_connection_id: email_connection_id,
          email_generation: generation, revoked_at: nil).where('expires_at > ?', Time.current).exists?
      end
    else
      false
    end
  rescue ActiveRecord::ActiveRecordError, GraduateAuthentication::Rejected
    false
  end

  def self.revoke(token)
    return unless valid_token?(token)

    where(token_digest: Digest::SHA256.hexdigest(token), revoked_at: nil).update_all(revoked_at: Time.current)
  end

  def self.revoke_for_student(student_id)
    identities = GraduateIdentity.where(student_id: student_id).select(:id)
    connections = GraduateEmailConnection.where(student_id: student_id).select(:id)
    sessions = where(graduate_identity_id: identities).or(where(graduate_email_connection_id: connections))
    sessions.where(revoked_at: nil).order(:id).lock.each { |row| row.update_columns(revoked_at: Time.current) }
  end

  def self.write_student_lock!(student_id)
    affected = Student.where(id: student_id).update_all('blocked = blocked')
    raise GraduateAuthentication::Rejected unless affected == 1
  end

  def self.insert_token!(**attributes)
    token = SecureRandom.hex(32)
    create!(**attributes, token_digest: Digest::SHA256.hexdigest(token), expires_at: LIFETIME.from_now)
    token
  end

  def self.current_email_mapping?(connection, mapping, student_id)
    connection && connection.revoked_at.nil? && connection.verified_at && connection.student_id == student_id &&
      mapping && mapping.connection_id == connection.id && mapping.student_id == student_id &&
      mapping.normalized_address == connection.normalized_address
  end

  def self.positive_integer?(value)
    value.is_a?(Integer) && value.positive?
  end

  def self.valid_token?(token)
    token.is_a?(String) && TOKEN_FORMAT.match?(token)
  end
  private_class_method :valid_token?, :positive_integer?, :current_email_mapping?, :insert_token!, :write_student_lock!
end
