# frozen_string_literal: true

class AddEmailExternalToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :email_external, :string
    add_column :users, :first_name, :string
    add_column :users, :middle_name, :string
    add_column :users, :last_name, :string
    Student.where(first_name: nil).find_each do |s|
      s.update(first_name: s.name)
    end
  end
end
