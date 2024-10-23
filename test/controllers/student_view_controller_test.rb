# frozen_string_literal: true

require 'test_helper'

class StudentViewControllerTest < ActionController::TestCase
  should 'not be able to access without loging in' do
    get :index
    assert_redirected_to login_url
  end

  context 'as student' do
    setup do
      @student = create(:student)
      log_user_in(@student)
    end

    should 'pre load student object for all actions' do
      get :index
      assert assigns(:student)

      get :details
      assert assigns(:student)
    end

    should 'redirect to thesis if there is one thesis' do
      create(:thesis, student: @student)
      get :index

      thesis = assigns(:thesis)
      assert thesis, 'Thesis should not be empty'
      assert_response :redirect
      assert_redirected_to student_view_thesis_process_path(thesis, Thesis::PROCESS_BEGIN),
                           'Should redirect to the first step in thesis submission process'
    end

    should 'show which thesis to work on, if more then one' do
      create_list(:thesis, 2, student: @student)
      get :index
      assert_response :success
      assert_template :index
      theses = assigns(:theses)
      assert theses, 'There are some theses'
      assert_equal 2, theses.size, 'Just one for now'
    end

    should 'avoid routing if files are not uploaded' do
      thesis = create(:thesis, student: @student)

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_UPLOAD }
      assert assigns(:thesis)
      assert_response :success
      assert_template 'upload'
      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_REVIEW }
      assert_response :success
      assert_template 'upload'
      assert_match(/Please upload a Primary Thesis File./, flash[:error])
    end

    should 'load thesis object and display or redirect to proper process step' do
      thesis = create(:thesis, student: @student)
      create(:document, thesis_id: thesis.id, user_id: @student.id, supplemental: false,
                        file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_BEGIN }
      assert assigns(:thesis)
      assert_response :success
      assert_template 'begin'

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_UPDATE }
      assert assigns(:thesis)
      assert_response :success
      assert_template 'update'

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_UPLOAD }
      assert assigns(:thesis)
      assert assigns(:primary_documents)
      assert assigns(:supplemental_documents)
      assert_response :success
      assert_template 'upload'

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_REVIEW }
      assert assigns(:thesis)
      assert assigns(:primary_documents)
      assert assigns(:supplemental_documents)
      assert_response :success
      assert_template 'review'

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_SUBMIT }
      assert assigns(:thesis)
      assert_response :success
      assert_template 'submit'

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_STATUS }
      assert assigns(:thesis)
      assert_response :success
      assert_template 'status'
    end

    should 'redirect to status if thesis status is anything by OPEN on process step is not status or review' do
      thesis = create(:thesis, student: @student, status: Thesis::UNDER_REVIEW)
      create(:document, thesis_id: thesis.id, user_id: @student.id, supplemental: false,
                        file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_UPLOAD }
      assert_template 'status'
      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_BEGIN }
      assert_template 'status'
      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_UPDATE }
      assert_template 'status'
      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_SUBMIT }
      assert_template 'status'
    end

    should 'not load a thesis belonging to another student' do
      thesis = create(:thesis)

      assert_raises ActiveRecord::RecordNotFound do
        get :thesis_process_router, params: { id: thesis.id, process_step: 'whatever' }
      end
    end
  end

  ######### LOGIN AND LOGGOUT AS STUDENT ##############

  should 'login as student' do
    student = create(:student)
    user = create(:user, role: User::ADMIN)
    log_user_in(user)

    assert_nothing_raised do
      get :login_as_student, params: { id: student.id }

      assert assigns(:student), 'student object was assgined'

      assert_equal session[:return_to_user_id], user.id, 'Return to id is the previously logged in user'
      assert_equal session[:user_id], student.id, 'Student id is now the current user id'
      assert_redirected_to student_view_index_path, 'Redirected to student view index path'
    end
  end

  should 'redirect back to students list if student you trying to login as is not found' do
    user = create(:user, role: User::ADMIN)
    log_user_in(user)

    get :login_as_student, params: { id: 9_999_999 }

    assert_redirected_to students_path, 'Student is not found'
    assert_equal flash[:alert], 'No such student found'
  end

  should 'log out as, if logged in as' do
    student = create(:student)
    user = create(:user, role: User::ADMIN)

    session[:user_id] = student.id
    session[:return_to_user_id] = user.id
    assert_nothing_raised do
      get :logout_as_student
      assert_redirected_to student_path(student)
      assert_equal session[:user_id], user.id
      assert_nil session[:return_to_user_id]
    end
  end
end
