# frozen_string_literal: true

class ChangeThesisTitleToText < ActiveRecord::Migration[5.0]
  def change
    change_column :theses, :title, :text
  end
end
