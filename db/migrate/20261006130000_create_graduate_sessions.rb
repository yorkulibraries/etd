# frozen_string_literal: true

class CreateGraduateSessions < ActiveRecord::Migration[7.0]
  def change
    create_table :graduate_sessions do |t|
      t.references :graduate_identity, null: false, foreign_key: { on_delete: :cascade }
      digest_options = { limit: 64, null: false }
      digest_options[:collation] = 'utf8mb4_bin' if connection.adapter_name == 'Mysql2'
      t.string :token_digest, **digest_options
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :graduate_sessions, :token_digest, unique: true
  end
end
