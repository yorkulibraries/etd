class AddReasonToThesis < ActiveRecord::Migration[7.0]
  def change
    add_column :theses, :returned_message, :string
  end
end
