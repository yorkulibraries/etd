# frozen_string_literal: true

class AddEmbargoAttributesToTheses < ActiveRecord::Migration[5.0]
  def change
    add_column :theses, :embargoed_at, :datetime
    add_column :theses, :embargoed_by_id, :integer
  end
end
