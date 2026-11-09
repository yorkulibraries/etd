# frozen_string_literal: true

# Makes the website export safe to run by staff:
# - export_logs.active_slot is 1 while an export is waiting or running and empty otherwise. The unique
#   index lets the database refuse a second active export even if two requests arrive together.
# - thesis_deposit_attempts records each thesis send before it starts. open_thesis_id stays set while a
#   send is in progress or its result is uncertain, so the same thesis cannot be sent twice.
# - start, finish and cancel times keep the time of day, not just the date.
class AddDepositSafetyToExports < ActiveRecord::Migration[7.0]
  TIME_COLUMNS = %i[job_started_at job_completed_at job_cancelled_at].freeze

  def change
    reversible do |direction|
      TIME_COLUMNS.each do |column|
        direction.up { change_column :export_logs, column, :datetime }
        direction.down { change_column :export_logs, column, :date }
      end
    end

    add_column :export_logs, :active_slot, :integer
    add_column :export_logs, :needs_checking_count, :integer, default: 0, null: false
    add_index :export_logs, :active_slot, unique: true

    create_table :thesis_deposit_attempts do |t|
      t.integer :thesis_id, null: false
      t.integer :export_log_id, null: false
      t.string :state, null: false
      t.integer :open_thesis_id
      t.string :sword_location
      t.string :licence_handoff
      t.text :error_message
      t.timestamps
    end
    add_index :thesis_deposit_attempts, :thesis_id
    add_index :thesis_deposit_attempts, :export_log_id
    add_index :thesis_deposit_attempts, :open_thesis_id, unique: true
  end
end
