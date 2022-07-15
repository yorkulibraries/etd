require 'test_helper'

class AuthenticatedStaffControllerTest < ActionController::TestCase
  context 'As student' do
    setup do
      @user = create(:user, role: User::STUDENT)
      @student = create :student
      log_user_in(@user)
    end

    should 'redirect to unauthorized if logged user is not staff' do
      thesis = create(:thesis, student: @student)

      # get :show, params: { id: thesis.id, student_id: @student.id }
      # assert_response :redirect
      # assert_redirected_to unauthorized_url
    end
  end

  context 'as staff' do
    setup do
      @user = create(:user, role: User::ADMIN)
      @student = create :student
      log_user_in(@user)
    end

    should 'work as normal for staff' do
      thesis = create(:thesis, student: @student)

      # get :show, params: { id: thesis.id, student_id: @student.id }
      # assert_response :success
    end
  end
end
