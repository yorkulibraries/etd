# frozen_string_literal: true

class CreateGraduateEmailAuthentication < ActiveRecord::Migration[7.0]
  def change
    create_table :graduate_email_controls, id: false do |t|
      t.bigint :id, null: false, primary_key: true, **(connection.adapter_name == 'Mysql2' ? { auto_increment: false } : {})
      t.boolean :enabled, null: false, default: false
      t.bigint :generation, null: false, default: 1
      t.integer :lock_version, null: false, default: 0
      t.timestamps
      t.check_constraint 'id = 1 AND generation > 0 AND lock_version >= 0', name: 'graduate_email_control_singleton'
    end
    reversible do |direction|
      direction.up { execute 'INSERT INTO graduate_email_controls (id, enabled, generation, lock_version, created_at, updated_at) VALUES (1, FALSE, 1, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)' }
    end

    create_table :graduate_email_connections do |t|
      user_reference(t, :student, cascade: true)
      user_reference(t, :approved_by)
      address(t)
      t.datetime :verified_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end

    create_table :graduate_email_approvals do |t|
      user_reference(t, :student, cascade: true)
      user_reference(t, :approved_by)
      address(t)
      t.string :token_digest, limit: 64, null: false
      t.bigint :generation, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.datetime :revoked_at
      t.references :replacement_of_connection, foreign_key: { to_table: :graduate_email_connections, on_delete: :cascade }, index: { name: 'idx_ge_approval_replacement' }
      t.timestamps
      t.check_constraint 'generation > 0', name: 'graduate_email_approval_generation'
    end
    add_index :graduate_email_approvals, :token_digest, unique: true, name: 'idx_ge_approval_token'

    create_table :graduate_email_active_addresses do |t|
      user_reference(t, :student, cascade: true, unique: true)
      t.references :connection, null: false, foreign_key: { to_table: :graduate_email_connections, on_delete: :cascade }, index: { unique: true, name: 'idx_ge_active_connection' }
      address(t)
      t.timestamps
    end
    add_index :graduate_email_active_addresses, :normalized_address, unique: true, name: 'idx_ge_active_address'

    create_table :graduate_email_challenges do |t|
      t.string :public_id, limit: 64, null: false
      t.references :approval, foreign_key: { to_table: :graduate_email_approvals, on_delete: :cascade }, index: { name: 'idx_ge_challenge_approval' }
      t.references :connection, foreign_key: { to_table: :graduate_email_connections, on_delete: :cascade }, index: { name: 'idx_ge_challenge_connection' }
      user_reference(t, :student, cascade: true, nullable: true)
      t.string :purpose, limit: 16, null: false
      t.string :browser_digest, limit: 64, null: false
      t.string :address_key, limit: 64
      t.bigint :generation, null: false
      t.datetime :expires_at, null: false
      t.string :state, limit: 16, null: false
      t.string :code_digest, limit: 64
      t.integer :failed_attempts, null: false, default: 0
      %i[claimed_at send_authorized_at sent_at consumed_at invalidated_at].each { |field| t.datetime field }
      t.timestamps
      t.check_constraint "(purpose = 'enroll' AND approval_id IS NOT NULL AND connection_id IS NULL AND student_id IS NOT NULL) OR (purpose = 'login' AND approval_id IS NULL AND connection_id IS NOT NULL AND student_id IS NOT NULL) OR (purpose = 'noop' AND approval_id IS NULL AND connection_id IS NULL AND student_id IS NULL AND address_key IS NULL)", name: 'graduate_email_challenge_target'
      t.check_constraint "state IN ('queued','noop','claimed','sending','sent','failed','superseded','revoked','consumed','expired')", name: 'graduate_email_challenge_state'
      t.check_constraint 'generation > 0 AND failed_attempts BETWEEN 0 AND 5', name: 'graduate_email_challenge_counts'
    end
    add_index :graduate_email_challenges, :public_id, unique: true, name: 'idx_ge_challenge_public'
    add_index :graduate_email_challenges, %i[browser_digest purpose], name: 'idx_ge_challenge_browser'
    add_index :graduate_email_challenges, :expires_at, name: 'idx_ge_challenge_expiry'

    create_table :graduate_email_limit_events do |t|
      t.string :kind, limit: 32, null: false
      t.string :key_digest, limit: 64, null: false
      t.datetime :occurred_at, null: false
      t.timestamps
      t.check_constraint "kind IN ('send_address','request_ip','verify_address','verify_student','verify_ip','admission_send','admission_verify')", name: 'graduate_email_limit_kind'
    end
    add_index :graduate_email_limit_events, %i[kind key_digest occurred_at], name: 'idx_ge_limit_window'

    create_table :graduate_email_cooldowns do |t|
      t.string :kind, limit: 32, null: false
      t.string :key_digest, limit: 64, null: false
      t.datetime :blocked_until, null: false
      t.timestamps
      t.check_constraint "kind IN ('verify_address','verify_student','verify_ip')", name: 'graduate_email_cooldown_kind'
    end
    add_index :graduate_email_cooldowns, %i[kind key_digest], unique: true, name: 'idx_ge_cooldown_key'

    create_table :graduate_email_audit_events do |t|
      { student: :users, actor: :users, connection: :graduate_email_connections,
        approval: :graduate_email_approvals, challenge: :graduate_email_challenges }.each do |name, table|
        t.references name, type: (table == :users ? :integer : :bigint),
          foreign_key: { to_table: table, on_delete: :nullify }, index: { name: "idx_ge_audit_#{name}" }
      end
      t.string :event, limit: 32, null: false
      t.string :outcome, limit: 32, null: false
      t.bigint :generation, null: false
      t.timestamps
      t.check_constraint 'generation > 0', name: 'graduate_email_audit_generation'
    end

    create_table :graduate_email_notices do |t|
      %i[old_connection replacement_connection].each do |name|
        t.references name, null: false, foreign_key: { to_table: :graduate_email_connections, on_delete: :cascade }, index: { name: "idx_ge_notice_#{name}", unique: name == :replacement_connection }
      end
      t.string :state, limit: 16, null: false, default: 'queued'
      t.datetime :claimed_at
      t.datetime :sent_at
      t.timestamps
      t.check_constraint "state IN ('queued','claimed','sent','failed')", name: 'graduate_email_notice_state'
    end
  end

  private

  def user_reference(table, name, cascade: false, nullable: false, unique: false)
    table.references name, type: :integer, null: nullable,
      foreign_key: { to_table: :users, **(cascade ? { on_delete: :cascade } : {}) },
      index: { name: "idx_#{table.name.to_s.sub('graduate_email_', 'ge_')}_#{name}", unique: unique }
  end

  def address(table)
    options = { limit: 254, null: false }
    options[:collation] = 'utf8mb4_bin' if connection.adapter_name == 'Mysql2'
    table.string :normalized_address, **options
  end
end
