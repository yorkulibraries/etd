require 'test_helper'

class CommitteeMembersControllerTest < ActionController::TestCase
  context 'as admin' do
    setup do
      @user = create(:user, role: User::ADMIN)
      @student = create(:student)
      @thesis = create(:thesis, student: @student)
      log_user_in(@user)
    end

    should 'show new committee_member page' do
      get :new, params: { thesis_id: @thesis.id, student_id: @student.id }
      assert_response :success
      assert_template :new
    end

    should 'create a committee member' do
      assert_difference 'CommitteeMember.count', 1 do
        post :create, params: {
          thesis_id: @thesis.id, student_id: @student.id, committee_member: attributes_for(:committee_member).except(:thesis)
        }
        member = assigns(:committee_member)
        assert member, 'Assigned a member object'
        assert_equal 0, member.errors.size, 'Ensure there are no errors'
        assert_equal @thesis.id, member.thesis.id, 'Sets the proper thesis object'
        assert_redirected_to student_thesis_path(@student, @thesis), 'Assert redirects to student form'
      end
    end

    should 'create a committee member with new_name attritube rather then the committee_member[:name]' do
      post :create, params: { thesis_id: @thesis.id, student_id: @student.id,
                              committee_member: { first_name: 'Jeromy', last_name: 'Clarkson', role: CommitteeMember::CHAIR } }
      member = assigns(:committee_member)
      assert_equal 'Clarkson, Jeromy', member.name, 'The name was taken from first_name, last_name attributes'
    end

    should 'destroy a committee member' do
      member = create(:committee_member, thesis: @thesis)

      assert_difference 'CommitteeMember.count', -1 do
        post :destroy, params: { thesis_id: @thesis.id, student_id: @student.id, id: member.id }
        member = assigns(:committee_member)
        assert_equal member.thesis.id, @thesis.id, 'Ensure the right commitee member is deleted'
        assert_redirected_to student_thesis_path(@student, @thesis), 'Assert redirects to student form'
      end
    end
  end
end
