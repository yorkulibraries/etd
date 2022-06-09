class RemoveSubjectsFromTheses < ActiveRecord::Migration[5.0]
  def up
    remove_column :theses, :subjects
  end

  def down
    add_comlumn :theses, :subjects, :string
  end
end
