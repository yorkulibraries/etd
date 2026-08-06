# frozen_string_literal: true

class CreateThesisSubmissionDocuments < ActiveRecord::Migration[7.0]
  def change
    create_table :thesis_submission_documents, id: :integer do |t|
      t.integer :thesis_submission_version_id, null: false
      t.integer :source_document_id
      t.boolean :supplemental, default: true, null: false
      t.integer :usage, null: false
      t.string :name
      t.string :original_filename
      t.string :content_type
      t.bigint :file_size
      t.string :file

      t.timestamps
    end

    add_index :thesis_submission_documents, :thesis_submission_version_id, name: 'index_submission_documents_on_version_id'
    add_index :thesis_submission_documents, :source_document_id
  end
end
