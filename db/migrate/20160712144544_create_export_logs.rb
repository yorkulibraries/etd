# frozen_string_literal: true

class CreateExportLogs < ActiveRecord::Migration[5.0]
  def change
    create_table :export_logs do |t|
      t.integer :user_id
      t.date :published_date
      t.boolean :production_export, default: false
      t.boolean :complete_thesis, default: true
      t.boolean :publish_thesis, default: true
      t.text :theses_ids
      t.integer :theses_count
      t.integer :failed_count
      t.integer :successful_count
      t.text :failed_ids
      t.text :successful_ids
      t.text :output_full
      t.text :output_error
      t.string :job_id
      t.string :job_status
      t.date :job_started_at
      t.date :job_completed_at
      t.date :job_cancelled_at
      t.integer :job_cancelled_by_id
      t.timestamps null: false
    end
  end
end
