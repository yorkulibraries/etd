# frozen_string_literal: true

require 'test_helper'

class UserTest < ActiveSupport::TestCase
  should 'create a valid user, required attrs are email, username, name, and blocked should be false' do
    user = build(:user)

    assert user.valid?

    assert_difference 'User.count', 1 do
      user.save
    end

    assert !user.blocked?, "User shouldn't be blocked"

    assert_equal User::STAFF, user.role, "Default role should be #{User::STAFF}"
  end

  should 'not create an invalid user' do
    user = build(:user, username: nil)
    assert !user.valid?, 'User should be invalid, since username is not specified'

    assert_no_difference 'User.count' do
      user.save
    end

    assert !build(:user, email: nil).valid?, 'Email is required'
    assert !build(:user, name: nil).valid?, 'Name is required'
    assert !build(:user, role: nil).valid?, 'Role is required'

    user = build(:user, email: 'randomfakenonworkingemail')
    assert !user.valid?, 'Email must follow a user@email.com format'

    user = build(:user, username: '@whatever')
    assert !user.valid?, "This is ain't twitter, use proper usernames"
  end

  should 'only create users with unique usernames and emails' do
    create(:user, username: 'unique', email: 'tester@test.com')
    user = build(:user, username: 'unique')
    assert !user.valid?, 'Trying to create a non-unique username'

    assert_no_difference 'User.count' do
      user.save
    end

    u = build(:user, username: 'whatever', email: 'tester@test.com')
    assert !u.valid?, 'Try to create a user with a non-unique email'
  end

  should 'list active or inactive users, active have blocked = false, inactive have blocked = true' do
    create_list(:user, 20, blocked: true)
    create_list(:user, 5, blocked: false)

    assert_equal 20, User.blocked.size, 'There should be 20 blocked users'
    assert_equal 5, User.active.size, 'There should be 5 active users'
  end

  should 'list only users, not students' do
    create_list(:user, 5, role: User::STAFF)
    create_list(:user, 2, role: User::STUDENT)

    assert_equal 5, User.not_students.count, 'There should be 5 non-student users'
    assert_equal 7, User.count, 'There should be a total of 7 users'
  end

  should 'only list active non student users' do
    student_owner = create(:user)
    create_list(:user, 2, role: User::STAFF, blocked: false)
    create_list(:user, 4, role: User::ADMIN, blocked: true)
    create_list(:student, 3, created_by: student_owner)

    assert_equal 3, User.active.not_students.count, 'There should only be 2 active, non-student users'
  end

  should 'not destroy user if destroy method is called' do
    user = create(:user)

    assert_difference 'User.count', -1 do
      user.destroy
    end
  end

  should 'block user' do
    user = create(:user, blocked: false)
    assert !user.blocked?, 'User should not be blocked'
    user.block

    User.find(user.id)
    assert user.blocked?, 'User should be blocked'
  end

  should 'Unblock user' do
    user = create(:user, blocked: true)

    assert user.blocked?, 'User should be blocked first'
    user.unblock

    u = User.find(user.id)

    assert !u.blocked?, 'User should be unblocked'
  end

  should 'display created by name if even if its nil' do
    user = create(:user)

    assert_not_nil user.created_by_name

    user = create(:user, created_by: nil)
    assert_not_nil user.created_by_name
  end

  should 'return true if user is not blocked' do
    user = create(:user, blocked: false)

    assert user.active?, 'Should be true'
  end

  should 'find by sisid if its a number or by username if its not' do
    student = create(:student, sisid: '123123123')
    user = create(:user, username: 'username')

    assert_nil User.find_active_user(nil), 'Returns nil if criteria is nil'

    s = User.find_active_user('123123123')

    assert_not_nil s, 'Student should be found'
    assert_equal student.id, s.id, 'Found student by number'

    u = User.find_active_user('username')
    assert_equal user.id, u.id, 'Found user by username'
  end
end
