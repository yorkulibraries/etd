class CreateLocSubjects < ActiveRecord::Migration[5.0]
  def change
    create_table :loc_subjects do |t|
      t.string :name
      t.string :category
      t.integer :code
      t.string :callnumber

      t.timestamps
    end
  end
end
