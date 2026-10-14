# frozen_string_literal: true

class CreateDspaceDeposits < ActiveRecord::Migration[7.0]
  def change
    create_table :dspace_deposits, options: 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb3' do |t|
      t.references :thesis, type: :integer, null: false, foreign_key: true
      t.references :export_log, type: :integer, null: false, foreign_key: true
      t.string :item_uuid, limit: 36, null: false
      t.string :sword_location
      t.string :license_status, null: false, default: 'pending'
      t.datetime :license_synced_at
      t.text :last_error

      t.timestamps
    end

    add_index :dspace_deposits, :item_uuid, unique: true
    add_index :dspace_deposits, %i[export_log_id thesis_id], unique: true
  end
end
