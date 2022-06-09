class CreateGemRecords < ActiveRecord::Migration[5.0]
  def self.up
    create_table :gem_records do |t|
      t.string :studentname
      t.integer :sisid
      t.string :emailaddress
      t.string :eventtype
      t.string :eventdate
      t.string :examresult
      t.text :title
      t.string :program
      t.string :superv
      t.timestamps
    end
  end

  def self.down
    drop_table :gem_records
  end
end
