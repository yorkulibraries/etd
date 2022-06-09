require 'test_helper'

class CommitteeMemberTest < ActiveSupport::TestCase

  should "create a valid committee member" do
    member = build(:committee_member)
    assert_difference "CommitteeMember.count", 1 do
      member.save
    end

  end

  should "not create an invalid member" do

    assert ! build(:committee_member, first_name: nil).valid?, "First Name is required"
    assert ! build(:committee_member, last_name: nil).valid?, "Last Name is required"
    assert ! build(:committee_member, role: nil).valid?, "Role is required"
    # assert ! build(:committee_member, thesis: nil).valid?, "Thesis is required"
  end


  should "destroy member" do
    member = create(:committee_member)

    assert_difference "CommitteeMember.count", -1 do
      member.destroy
    end

  end

  should "show full_name if first name or last name are empty" do
    n = build(:committee_member, first_name: nil, last_name: nil, full_name: "Something")
    n.save(validate: false)
    assert_equal "Something", n.name

    n2 = build(:committee_member, first_name: "Test", last_name: nil, full_name: "Something")
    n2.save(validate: false)
    assert_equal ", Test", n2.name

    n3 = build(:committee_member, last_name: "Test", first_name: nil, full_name: "Something")
    n3.save(validate: false)
    assert_equal "Test, ", n3.name


    n4 = create(:committee_member, last_name: "Test", first_name: "Machine", full_name: "Something")
    assert_equal "Test, Machine", n4.name

  end

end
