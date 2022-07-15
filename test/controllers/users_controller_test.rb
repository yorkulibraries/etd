require 'test_helper'

class UsersControllerTest < ActionController::TestCase
  context 'as admin' do
    setup do
      @user = create(:user, role: User::ADMIN, name: 'System User')
      log_user_in(@user)
    end

    should 'be able to show the new user form. Role select should be present, sisid field should not' do
      get :new

      assert assigns(:user)

      assert_select 'form#new_user', 1, 'An HTML Form should be present'
      assert_select 'input#user_sisid', 0, 'SISID should not be visible'
      assert_select 'select#user_role', 1, 'User role should have a drop down'
    end

    should 'be able to create new users, makes sure that created by id is assigned' do
      user_attrs = attributes_for(:user, role: User::MANAGER)

      assert_difference 'User.count', 1 do
        post :create, params: { user: user_attrs.except(:created_by_id, :blocked) }
      end
      user = assigns(:user)
      assert user, 'User object was assigned'
      assert_equal @user.id, user.created_by.id, 'user created by should be as the current user'
      assert_equal User::MANAGER, user.role, "user role should be #{User::MANAGER}"

      assert_redirected_to users_path
    end

    should 'be able to list all active users on the index page, alphabetically' do
      u1 = create(:user, name: 'Xavier')
      create(:user, name: 'Aaron')
      create(:user, name: 'John')

      create(:user, name: 'Blocked', blocked: true)

      get :index

      users = assigns(:users)
      assert users, 'Users array should be assigned'
      assert_equal 4, users.size, 'Should return 3+1 active users'
      assert_equal 'Aaron', users.first.name, 'First one should be Aaron'
      assert_equal 'Xavier', users.last.name, 'Last one should be Xavier'
    end

    should 'show edit page' do
      u = create(:user)

      get :edit, params: { id: u.id }

      user = assigns(:user)
      assert user, "User can't be nil"
      assert_equal u.id, user.id, 'Ids should match'

      assert_select "form#edit_user_#{u.id}", 1, ' An HTML Form should be present'
    end

    should 'be able to update existing users' do
      user = create(:user, role: User::STAFF, created_by: @user, name: 'test')

      post :update, params: { id: user.id, user: { role: User::MANAGER, name: 'test2' } }

      updated_user = assigns(:user)
      assert updated_user, 'User object was assigned'
      assert_equal 'test2', updated_user.name, "User's name should have been changed"
      assert_equal User::MANAGER, updated_user.role, 'New role should be MANAGER'
      assert_equal @user.id, updated_user.created_by.id, 'Created by id should be the same as the user who created it'

      assert_redirected_to users_path, 'Should redirect to users path'
    end

    should 'be able to block users, except for yourself. There is no deleting users. ' do
      u = create(:user, role: User::STAFF, created_by: @user)

      assert_no_difference 'User.count' do
        post :destroy, params: { id: u.id }
      end

      assert_redirected_to users_url

      post :destroy, params: { id: @user.id }

      @user.reload

      assert_equal false, @user.blocked?, "Can't disable myself"
      assert_equal 'You are not allowed to disable yourself', flash[:alert]
    end

    should 'be able to list all Users on the index page, but not students' do
      create_list(:user, 5, role: User::STAFF)
      create_list(:user, 2, role: User::STUDENT)

      get :index
      users = assigns(:users)

      assert_equal 6, users.count, 'There are only 5 + 1 @user, active non-student users'
    end

    should 'not try to show Student as user, if Student id is passed to show page, same for edit or update' do
      student = create(:student)

      assert_raises ActiveRecord::RecordNotFound, 'Should throw Active Record Not Found exception' do
        get :show, params: { id: student.id }
        get :edit, params: { id: student.id }
        post :update, params: { id: student.id }
        post :destroy, params: { id: student.id }
      end
    end

    should 'list active users on index page' do
      create_list(:user, 5, blocked: true)
      create_list(:user, 3, blocked: false)
      create_list(:student, 4, created_by: @user)

      get :index
      users = assigns(:users)
      assert_equal 4, users.count, 'There should only be 3 active users + 1 currently signed in user'
    end

    should 'group by role and displaying the users' do
      create_list(:user, 3, role: User::STAFF)
      create_list(:user, 2, role: User::ADMIN)
      create_list(:user, 4, role: User::STAFF, blocked: true)

      get :index
      users = assigns(:users)
      user_groups = assigns(:user_groups)
      assert user_groups, 'should list user groups'
      assert_equal 2, user_groups.count, 'Should list two user groups'

      user_groups = nil

      get :blocked

      user_groups = assigns(:user_groups)
      assert user_groups, 'Should have the user_groups'
      assert_equal 1, user_groups.count, 'Should only have one user group'
    end

    should 'list blocked users, excluding students' do
      create_list(:user, 5, blocked: true)
      create_list(:user, 4, blocked: false)
      create_list(:student, 3)

      get :blocked
      assert_template 'index'
      users = assigns(:users)
      assert_equal 5, users.count, 'There should be 5 inactive users'
    end

    should "Block the user, make sure can't block yourself" do
      user = create(:user, blocked: false)

      post :block, params: { id: user.id }

      assert_redirected_to users_path, 'Should redirect to users path'
      user.reload
      assert user.blocked?, 'User should be blocked'

      post :block, params: { id: @user.id }

      @user.reload
      assert !@user.blocked?, "Make sure you can't block yourself"
    end

    should 'Unblock the user' do
      user = create(:user, blocked: true)

      post :unblock, params: { id: user.id }

      assert_redirected_to blocked_users_path, 'Should redirect back to blocked users list'
      user.reload
      assert !user.blocked?, 'User should not be blocked'
    end
  end
end
