# frozen_string_literal: true

class ChangeEventdateTypeInGemRecords < ActiveRecord::Migration[5.0]
  def up
    change_column :gem_records, :eventdate, :date
  end

  def down
    change_column :gem_records, :eventdate, :string
  end
end
