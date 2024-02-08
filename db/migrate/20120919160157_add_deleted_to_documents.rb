# frozen_string_literal: true

class AddDeletedToDocuments < ActiveRecord::Migration[5.0]
  def change
    add_column :documents, :deleted, :boolean, default: false
  end
end
