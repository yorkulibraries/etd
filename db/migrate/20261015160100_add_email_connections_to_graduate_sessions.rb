# frozen_string_literal: true

class AddEmailConnectionsToGraduateSessions < ActiveRecord::Migration[7.0]
  def up
    change_column_null :graduate_sessions, :graduate_identity_id, true
    add_reference :graduate_sessions, :graduate_email_connection,
      foreign_key: { on_delete: :cascade }, index: { name: 'idx_graduate_session_email' }
    add_column :graduate_sessions, :authentication_method, :string, limit: 16, default: 'google'
    execute "UPDATE graduate_sessions SET authentication_method = 'google' WHERE authentication_method IS NULL"
    change_column_null :graduate_sessions, :authentication_method, false
    add_column :graduate_sessions, :email_generation, :bigint
    add_check_constraint :graduate_sessions,
      "(authentication_method = 'google' AND graduate_identity_id IS NOT NULL AND graduate_email_connection_id IS NULL AND email_generation IS NULL) OR (authentication_method = 'email' AND graduate_identity_id IS NULL AND graduate_email_connection_id IS NOT NULL AND email_generation IS NOT NULL AND email_generation > 0)",
      name: 'graduate_session_exclusive_method'
  end

  def down
    # Email sessions have no representation in the old schema. Google rows survive.
    execute "DELETE FROM graduate_sessions WHERE authentication_method = 'email'"
    remove_check_constraint :graduate_sessions, name: 'graduate_session_exclusive_method'
    remove_column :graduate_sessions, :email_generation
    remove_column :graduate_sessions, :authentication_method
    remove_reference :graduate_sessions, :graduate_email_connection, foreign_key: true
    change_column_null :graduate_sessions, :graduate_identity_id, false
  end
end
