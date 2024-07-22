class AddNotesToTheses < ActiveRecord::Migration[7.0]
  def change
    add_column :theses, :notes, :text
  end
end
