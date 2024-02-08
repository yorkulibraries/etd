# frozen_string_literal: true

class CreateDocuments < ActiveRecord::Migration[5.0]
  def self.up
    create_table :documents do |t|
      t.references :thesis
      t.references :user
      t.boolean :supplemental
      t.string :name
      t.timestamps
    end
  end

  def self.down
    drop_table :documents
  end
end
