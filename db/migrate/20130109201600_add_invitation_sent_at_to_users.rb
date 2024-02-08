# frozen_string_literal: true

class AddInvitationSentAtToUsers < ActiveRecord::Migration[5.0]
  def change
    add_column :users, :invitation_sent_at, :date
  end
end
