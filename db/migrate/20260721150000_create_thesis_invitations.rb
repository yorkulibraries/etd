class CreateThesisInvitations < ActiveRecord::Migration[7.0]
  def change
    create_table :thesis_invitations do |t|
      t.references :student, null: false, type: :integer, foreign_key: { to_table: :users }
      t.references :gem_record, type: :integer, foreign_key: true
      t.references :thesis, type: :integer, foreign_key: true
      t.datetime :sent_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at

      t.timestamps
    end
  end
end
