# frozen_string_literal: true

class CreateThesisSubmissionVersions < ActiveRecord::Migration[7.0]
  def change
    create_table :thesis_submission_versions, id: :integer do |t|
      t.integer :thesis_id, null: false
      t.integer :version_number, null: false
      t.integer :submitted_by_id, null: false
      t.datetime :submitted_at, null: false

      t.timestamps
    end

    add_index :thesis_submission_versions, :thesis_id
    add_index :thesis_submission_versions, :submitted_by_id
    add_index :thesis_submission_versions, [:thesis_id, :version_number], unique: true, name: 'index_submission_versions_on_thesis_and_version'
  end
end
