# frozen_string_literal: true

require 'test_helper'

class StudentTest < ActiveSupport::TestCase
  should 'create a new student if valid data is supplied' do
    student = build(:student, name: 'student')

    assert_difference 'Student.count', 1 do
      student.save
    end
  end

  should 'require username, sisid, name and email, sisid must be excactly 9 chars long' do
    assert !build(:student, name: nil).valid?, 'Name is required'
    assert !build(:student, sisid: nil).valid?, 'SISID is required'
    assert !build(:student, email: nil).valid?, 'Email is required'
    assert !build(:student, username: nil).valid?, 'Username is required'

    assert !build(:student, sisid: '1234').valid?, 'SISID must be 9 chars long'
    assert !build(:student, sisid: '1234567890909').valid?, 'SISID must be exactly 9 chars long'
  end

  should 'have sisid, username and email unique' do
    create(:student, name: 'test', sisid: '123456789', email: 'test@test.com', username: 'test')

    assert !build(:student, sisid: '123456789').valid?, 'sisid exists already'
    assert !build(:student, email: 'test@test.com').valid?, 'email exists already'
    assert !build(:student, username: 'test').valid?, 'username exists'
  end

  should 'overwrite the destroy method to not destroy the student' do
    student = create(:student)

    assert_difference 'Student.count', -1 do
      student.destroy
    end
  end

  should 'list active students and inactive students, excluding users' do
    create_list(:user, 5, blocked: true)
    create_list(:student, 2, blocked: false)
    create_list(:student, 10, blocked: true)

    assert_equal 2, Student.active.count, 'There should be 2 active students'
    assert_equal 10, Student.blocked.count, 'There should be 10 inactive students'
    assert_equal 15, User.blocked.count, 'There should be 15 inactive users'
  end

  should 'accept multiple email address, comma or space separated' do
    comma_separated = 'test@test.com, user@user.com, woot@woot.com'
    space_separated = comma_separated.split(',').join(' ')
    one_invalid = 'test@test.com woot'

    assert build(:student, email: comma_separated).valid?, '3 Emails supplied, comma separated.'
    assert build(:student, email: space_separated).valid?, '3 Emails supplied, space separated.'
    assert build(:student, email: 'one@email.com').valid?, '1 email only'

    assert !build(:student, email: one_invalid).valid?, 'should fail since one email is invalid'
  end

  should 'unblock the student if student is blocked' do
    student = create(:student, blocked: true)

    assert student.blocked?, 'Student should be blocked first.'
    student.unblock

    s = Student.find(student.id)
    assert !s.blocked, 'Student should be unblocked'
  end

  ### FIND BY SISID OR NAME ###
  should 'find students by sisid or name' do
    create(:student, name: 'John Smith', sisid: '111111111')
    create(:student, name: 'John Doe', sisid: '222222222')

    assert_equal 1, Student.find_by_sisid_or_name('222222222').size, 'one with sisid 222'
    assert_equal 1, Student.find_by_sisid_or_name('doe').size, 'One doe'
    assert_equal 2, Student.find_by_sisid_or_name('john').size, 'Should be two Johns'
    assert_equal 0, Student.find_by_sisid_or_name('brandon').size, 'No one was found'
  end

  should 'Auto populate first_name' do
    student = create(:student, name: 'John Smith', sisid: '111111111')
    assert_equal student.first_name, 'John Smith'
    student.save
    assert_equal student.first_name, 'John Smith'
  end

  should 'Validate extra information when validate_secondary_info is true' do
    student = create(:student, name: 'John Smith', sisid: '111111111')
    student.validate_secondary_info = true
    student.save
    assert_includes(student.errors[:email_external], "can't be blank")
  end

  should 'Validate email external / non-YorkU email does not contain YorkU address' do
    student = create(:student, name: 'John Smith', sisid: '111111111')
    student.validate_secondary_info = true
    student.email_external = 'john@yorku.ca'
    student.save
  
    assert_includes student.errors[:email_external], 'cannot be a yorku.ca domain. Please add an external email.'

  end

  should 'do not allow student to [new, create, delete] a committee member for their own thesis' do

    # Reference: ability.rb
    # can %i[new create destroy], CommitteeMember do |committee|
    #   committee.thesis.student_id == user.id
    # end

    @student = create(:student)
    @thesis = create(:thesis, student: @student)
    member = create(:committee_member, thesis: @thesis)
    committee_member = @thesis.committee_members.first

    # puts "\n**************************"
    # puts "\nStudent: #{@student.inspect}"
    # puts "\nThesis: #{@thesis.inspect}"
    # puts "\nMember: #{member.inspect}"
    # puts "\nCommitteeMember: #{committee_member.inspect}"
    # puts "\n**************************"

    @ability = Ability.new(@student)
    assert @ability.cannot?(:new, committee_member), "student should not be allowed to add new committee members to thesis"
    assert @ability.cannot?(:create, committee_member), "student should not be allowed to create committee members to thesis"
    assert @ability.cannot?(:destroy, committee_member), "student should not be allowed to delete committee members to thesis"


  end

end
