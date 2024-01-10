# frozen_string_literal: true

class CreateThesisSubjectships < ActiveRecord::Migration[5.0]
  def change
    create_table :thesis_subjectships do |t|
      t.integer :thesis_id
      t.integer :loc_subject_id
      t.integer :rank

      t.timestamps
    end
  end
end
