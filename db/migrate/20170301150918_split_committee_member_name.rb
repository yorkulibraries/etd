# frozen_string_literal: true

class SplitCommitteeMemberName < ActiveRecord::Migration[5.0]
  def change
    add_column :committee_members, :first_name, :string
    add_column :committee_members, :last_name, :string
    rename_column :committee_members, :name, :full_name
  end
end
