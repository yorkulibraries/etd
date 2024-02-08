# frozen_string_literal: true

class AddExamDateToGemRecords < ActiveRecord::Migration[5.0]
  def change
    add_column :gem_records, :examdate, :date
  end
end
