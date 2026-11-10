# frozen_string_literal: true

class CreateThesisReplacedDocuments < ActiveRecord::Migration[7.0]
  def change
    create_table :thesis_replaced_documents, id: :integer do |t|
      t.integer :thesis_id, null: false
      t.integer :source_document_id
      t.integer :replaced_by_id, null: false
      t.datetime :replaced_at, null: false
      t.boolean :supplemental, default: true, null: false
      t.integer :usage, null: false
      t.string :name
      t.string :original_filename
      t.string :content_type
      t.bigint :file_size
      t.string :file

      t.timestamps
    end

    add_index :thesis_replaced_documents, :thesis_id
    add_index :thesis_replaced_documents, :source_document_id
  end
end
