# frozen_string_literal: true

class AddExtraDatesToThesis < ActiveRecord::Migration[5.0]
  def change
    add_column :theses, :student_accepted_terms_at, :date
    add_column :theses, :under_review_at, :date
    add_column :theses, :accepted_at, :date
    add_column :theses, :published_at, :date
    add_column :theses, :returned_at, :date
  end
end
