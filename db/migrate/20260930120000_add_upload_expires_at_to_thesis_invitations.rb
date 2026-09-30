class AddUploadExpiresAtToThesisInvitations < ActiveRecord::Migration[7.0]
  def up
    add_column :thesis_invitations, :upload_expires_at, :datetime
    ThesisInvitation.reset_column_information
    ThesisInvitation.where(upload_expires_at: nil).update_all('upload_expires_at = expires_at')
    change_column_null :thesis_invitations, :upload_expires_at, false
  end

  def down
    remove_column :thesis_invitations, :upload_expires_at
  end
end
