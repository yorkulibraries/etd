# frozen_string_literal: true

class AddEmbargoFlagToTheses < ActiveRecord::Migration[5.0]
  def change
    add_column :theses, :embargoed, :boolean, default: false
  end
end
