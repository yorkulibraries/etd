# frozen_string_literal: true

class AddRequestUuidToAudits < ActiveRecord::Migration[5.0]
  def self.up
    add_column :audits, :request_uuid, :string
    add_index :audits, :request_uuid
  end

  def self.down
    remove_column :audits, :request_uuid
  end
end
