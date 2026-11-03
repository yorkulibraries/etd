# frozen_string_literal: true

# A graduate may connect email sign-in by proving they own an address already
# on their student record. Those approvals and connections have no staff
# approver; source records which path created them.
class AllowRecordMatchedEmailSignIn < ActiveRecord::Migration[7.0]
  TABLES = %i[graduate_email_approvals graduate_email_connections].freeze

  def change
    TABLES.each do |table|
      add_column table, :source, :string, limit: 16, null: false, default: 'staff'
      change_column_null table, :approved_by_id, true
      add_check_constraint table, "(source = 'staff' AND approved_by_id IS NOT NULL) OR (source = 'record' AND approved_by_id IS NULL)",
        name: "#{table.to_s.delete_suffix('s')}_source"
    end
  end
end
