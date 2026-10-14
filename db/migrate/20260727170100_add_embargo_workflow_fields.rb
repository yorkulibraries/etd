# frozen_string_literal: true

class AddEmbargoWorkflowFields < ActiveRecord::Migration[7.0]
  def change
    add_column :theses, :embargo_selection, :integer, null: false, default: 0
    # documents.id and embargo_requests.id are both int; see CreateEmbargoRequests.
    add_reference :documents, :embargo_request, null: true, type: :integer, foreign_key: true
  end
end
