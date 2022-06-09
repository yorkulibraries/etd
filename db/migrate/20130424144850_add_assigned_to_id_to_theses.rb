class AddAssignedToIdToTheses < ActiveRecord::Migration[5.0]
  def change
    add_column :theses, :assigned_to_id, :integer
  end
end
