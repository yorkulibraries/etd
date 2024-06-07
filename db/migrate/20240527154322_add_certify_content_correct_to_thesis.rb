class AddCertifyContentCorrectToThesis < ActiveRecord::Migration[7.0]
  def change
    add_column :theses, :certify_content_correct, :boolean, default: false
  end
end
