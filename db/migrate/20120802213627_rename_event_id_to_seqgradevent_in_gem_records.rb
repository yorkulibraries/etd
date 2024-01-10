# frozen_string_literal: true

class RenameEventIdToSeqgradeventInGemRecords < ActiveRecord::Migration[5.0]
  def up
    rename_column :gem_records, :event_id, :seqgradevent
  end

  def down
    rename_column :gem_records, :seqgradevent, :event_id
  end
end
