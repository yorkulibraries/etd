# frozen_string_literal: true

class AddEventIdToGemRecords < ActiveRecord::Migration[5.0]
  def change
    add_column :gem_records, :event_id, :integer
  end
end
