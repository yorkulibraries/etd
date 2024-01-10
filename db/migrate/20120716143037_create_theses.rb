# frozen_string_literal: true

class CreateTheses < ActiveRecord::Migration[5.0]
  def self.up
    create_table :theses do |t|
      t.string :title
      t.string :author
      t.string :supervisor
      t.text :committee
      t.references :student
      t.text :subjects
      t.text :keywords
      t.text :abstract
      t.text :embargo
      t.string :language
      t.string :degree_name
      t.string :degree_level
      t.string :program
      t.date :exam_date
      t.date :published_date
      t.string :status
      t.timestamps
    end
  end

  def self.down
    drop_table :theses
  end
end
