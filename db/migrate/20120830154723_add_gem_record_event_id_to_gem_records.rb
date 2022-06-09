class AddGemRecordEventIdToGemRecords < ActiveRecord::Migration[5.0]
  def change
    add_column :theses, :gem_record_event_id, :integer
  end
end
