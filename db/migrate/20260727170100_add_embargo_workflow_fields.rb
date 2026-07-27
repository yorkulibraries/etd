# frozen_string_literal: true

class AddEmbargoWorkflowFields < ActiveRecord::Migration[7.0]
  def change
    add_column :theses, :embargo_selection, :integer, null: false, default: 0
    add_reference :documents, :embargo_request, null: true, foreign_key: true
  end
end
