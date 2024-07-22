class AddGemRecordIdToCommitteeMembers < ActiveRecord::Migration[7.0]
  def change
    add_column :committee_members, :gem_record_id, :integer
  end
end
