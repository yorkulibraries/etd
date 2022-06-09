class CreateUsers < ActiveRecord::Migration[5.0]
  def self.up
    create_table :users do |t|
      t.string :username
      t.string :name
      t.string :type
      t.string :email
      t.integer :created_by_id
      t.boolean :blocked, :default => false
      t.string :role
      t.string :sisid
      t.timestamps
    end
  end

  def self.down
    drop_table :users
  end
end
