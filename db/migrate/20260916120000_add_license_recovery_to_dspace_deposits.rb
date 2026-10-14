class AddLicenseRecoveryToDspaceDeposits < ActiveRecord::Migration[7.0]
  def change
    add_column :dspace_deposits, :license_attempts, :integer, default: 0, null: false
    add_column :dspace_deposits, :license_retry_at, :datetime
    add_index :dspace_deposits, [:license_status, :license_retry_at]
  end
end
