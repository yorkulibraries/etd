# frozen_string_literal: true

class CreateEmbargoRequests < ActiveRecord::Migration[7.0]
  def change
    create_table :embargo_requests do |t|
      t.references :thesis, null: false, foreign_key: true
      t.integer :request_type, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.integer :reason
      t.text :rationale
      t.integer :requested_duration_months
      t.string :contact_phone
      t.string :contact_email
      t.string :graduate_program_director_name
      t.string :graduate_program_director_email
      t.string :supervisor_name
      t.string :supervisor_email
      t.datetime :submitted_at
      t.date :approved_until
      t.datetime :decided_at
      t.references :decided_by, foreign_key: { to_table: :users }
      t.text :decision_notes
      t.timestamps
    end

    add_index :embargo_requests, %i[thesis_id status]
    add_index :embargo_requests, :submitted_at
  end
end
