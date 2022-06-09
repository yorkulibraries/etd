class CreateCommitteeMembers < ActiveRecord::Migration[5.0]
  def change
    create_table :committee_members do |t|
      t.string :name
      t.string :role
      t.integer :thesis_id

      t.timestamps
    end
  end
end
