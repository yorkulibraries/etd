# frozen_string_literal: true

class CreateGraduateAuthentication < ActiveRecord::Migration[7.0]
  def change
    create_table :graduate_identities do |t|
      t.references :student, type: :integer, null: false, foreign_key: { to_table: :users }
      t.references :linked_by, type: :integer, foreign_key: { to_table: :users }
      t.string :provider, limit: 32, null: false
      uid_options = { limit: 191, null: false }
      uid_options[:collation] = 'utf8mb4_bin' if connection.adapter_name == 'Mysql2'
      t.string :uid, **uid_options
      t.string :link_method, limit: 32, null: false, default: 'ppy'
      t.timestamps
    end
    add_index :graduate_identities, %i[provider uid], unique: true
    add_index :graduate_identities, %i[student_id provider], unique: true

    create_table :graduate_authentication_invitations do |t|
      t.references :student, type: :integer, null: false, foreign_key: { to_table: :users }, index: { name: 'index_graduate_invitations_on_student' }
      t.references :approved_by, type: :integer, null: false, foreign_key: { to_table: :users }, index: { name: 'index_graduate_invitations_on_approver' }
      t.string :provider, limit: 32, null: false
      t.string :token_digest, limit: 64, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :graduate_authentication_invitations, :token_digest, unique: true, name: 'index_graduate_invitations_on_digest'
  end
end
