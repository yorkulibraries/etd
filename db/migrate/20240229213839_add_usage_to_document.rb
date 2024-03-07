class AddUsageToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :usage, :integer
    Document.update_all(usage: :thesis)
  end
end
