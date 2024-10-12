# frozen_string_literal: true

require 'test_helper'

class CommitteeMemberTest < ActiveSupport::TestCase
  should 'create a valid committee member' do
    member = build(:committee_member)
    assert_difference 'CommitteeMember.count', 1 do
      member.save
    end
  end

  should 'not create an invalid member' do
    assert !build(:committee_member, first_name: nil).valid?, 'First Name is required'
    assert !build(:committee_member, last_name: nil).valid?, 'Last Name is required'
    assert !build(:committee_member, role: nil).valid?, 'Role is required'
    # assert ! build(:committee_member, thesis: nil).valid?, "Thesis is required"
  end

  should 'destroy member' do
    member = create(:committee_member)

    assert_difference 'CommitteeMember.count', -1 do
      member.destroy
    end
  end
end
