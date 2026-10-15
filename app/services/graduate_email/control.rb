# frozen_string_literal: true

module GraduateEmail
  module Control
    # This capability belongs only to this connection's fresh transaction. A
    # yielded row, thread-local flag or nested transaction is not lock ownership.
    class << self
      def synchronize
        primary do
          connection = GraduateEmailControl.connection
          raise GraduateAuthentication::Rejected unless connection.open_transactions.zero?

          with_lock_timeout(connection) do
            GraduateEmailControl.uncached do
              GraduateEmailControl.transaction do
                affected = connection.update('UPDATE graduate_email_controls SET lock_version = lock_version + 1 WHERE id = 1')
                raise GraduateAuthentication::Rejected unless affected == 1

                control = GraduateEmailControl.find_by(id: 1)
                raise GraduateAuthentication::Rejected unless valid_state?(control)

                transaction = connection.transaction_manager.current_transaction
                connection.instance_variable_set(:@graduate_email_control_ownership, [transaction, control])
                begin
                  yield control
                ensure
                  connection.remove_instance_variable(:@graduate_email_control_ownership)
                end
              end
            end
          end
        end
      rescue ActiveRecord::ActiveRecordError
        raise GraduateAuthentication::Rejected, 'Graduate email unavailable', cause: nil
      end

      def enabled?
        return false unless GraduateEmail.configured?

        primary do
          GraduateEmailControl.uncached do
            control = GraduateEmailControl.find_by(id: 1)
            valid_state?(control) && control.enabled == true
          end
        end
      rescue ActiveRecord::ActiveRecordError, GraduateAuthentication::Rejected
        false
      end

      def set_enabled!(enabled:, actor_id:)
        raise GraduateAuthentication::Rejected unless [true, false].include?(enabled)

        synchronize do |control|
          # Actor is locked after control and before any subordinate artifacts.
          actor = User.lock.find_by(id: actor_id)
          raise GraduateAuthentication::Rejected unless GraduateAuthentication.staff_authorized?(actor) && !actor.is_a?(Student)

          generation = control.generation + (enabled ? 0 : 1)
          control.update!(enabled: enabled, generation: generation)
          Audit.record!(event: 'control', outcome: enabled ? 'enabled' : 'disabled', actor_id: actor.id, generation: generation)
          generation
        end
      end

      def locked_state!
        connection = GraduateEmailControl.connection
        ownership = connection.instance_variable_get(:@graduate_email_control_ownership)
        raise GraduateAuthentication::Rejected unless connection.transaction_open? && ownership &&
          ownership[0].equal?(connection.transaction_manager.current_transaction)

        ownership[1]
      end

      private

      # Session settings are scoped to this call and applied before BEGIN, so
      # the first operation in the fresh authentication transaction is a write.
      def with_lock_timeout(connection)
        case connection.adapter_name
        when 'SQLite'
          previous = connection.select_value('PRAGMA busy_timeout').to_i
          setting = 'PRAGMA busy_timeout = '
          bounded = [previous, 2000].min
        when 'Mysql2'
          previous = connection.select_rows("SHOW SESSION VARIABLES LIKE 'innodb_lock_wait_timeout'").first.last.to_i
          setting = 'SET SESSION innodb_lock_wait_timeout = '
          bounded = [previous, 2].min
        else
          raise GraduateAuthentication::Rejected
        end
        connection.execute("#{setting}#{bounded}")
        begin
          yield
        ensure
          connection.execute("#{setting}#{previous}")
        end
      end

      def primary(&block)
        ActiveRecord::Base.connected_to(role: :writing, &block)
      end

      def valid_state?(control)
        !control.nil? && control.generation.is_a?(Integer) && control.generation.positive? && [true, false].include?(control.enabled)
      end
    end
  end
end
