# frozen_string_literal: true

module GraduateEmail
  # Finds the one student record that lists an address as its primary
  # (email) or secondary (email_external) contact. Policy (FGS, 2026-11-03):
  # proving ownership of that address, by an emailed code or a verified
  # Google email, may connect sign-in to that record. Anything ambiguous
  # matches nothing, so FGS decides.
  module RecordMatch
    SEPARATORS = /[\s,;]+/

    Match = Struct.new(:student_id, :normalized_address, :approval)

    class << self
      # Every address a record lists, normalized; unsupported entries drop out.
      def addresses(user)
        [user.email, user.email_external].compact.flat_map { |field| field.to_s.split(SEPARATORS) }
          .filter_map { |entry| Address.normalize(input: entry) }.uniq
      end

      # The single student record listing this exact address, else nil. Every
      # student counts toward uniqueness, blocked or not: a duplicate anywhere
      # means FGS must decide. Callers still check the student is active.
      def owner_id(address)
        normalized = Address.normalize(input: address)
        return unless normalized

        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(normalized)}%"
        owners = Student.where('LOWER(users.email) LIKE :p OR LOWER(users.email_external) LIKE :p', p: pattern)
          .select { |student| addresses(student).include?(normalized) }
        owners.first.id if owners.size == 1
      end

      # Caller owns the Control lock, before any user lock. Lock order matches
      # enrollment: user, approvals, competing claims, connections, mappings.
      # Returns a Match (with any reusable pending record approval) or nil.
      def locate_locked(address:, control:, now:)
        normalized = Address.normalize(input: address)
        owner = normalized && owner_id(normalized)
        return unless owner

        student = User.where(id: owner).lock.first
        return unless GraduateAuthentication.active_student?(student) && owner_id(normalized) == student.id

        approvals = GraduateEmailApproval.where(student_id: student.id).order(:id).lock.to_a
        return if Enrollment.competing_locked(student_id: student.id, address: normalized, generation: control.generation, now: now).any?

        connections = GraduateEmailConnection.where(student_id: student.id).order(:id).lock.to_a
        return if connections.any? { |row| row.revoked_at.nil? }

        mappings = GraduateEmailActiveAddress.where('student_id = ? OR normalized_address = ?', student.id, normalized).order(:id).lock.to_a
        return if mappings.any?

        pending = approvals.find do |row|
          row.source == 'record' && row.normalized_address == normalized &&
            Enrollment.reserving?(row, generation: control.generation, now: now)
        end
        Match.new(student.id, normalized, pending)
      end
    end
  end
end
