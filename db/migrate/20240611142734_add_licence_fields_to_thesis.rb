class AddLicenceFieldsToThesis < ActiveRecord::Migration[7.0]
  def change
    add_column :theses, :lac_licence_agreement, :boolean, default: false
    add_column :theses, :yorkspace_licence_agreement, :boolean, default: false
    add_column :theses, :etd_licence_agreement, :boolean, default: false
  end
end
