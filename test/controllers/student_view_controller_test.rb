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
      assert_template 'embargo'
      assert_equal 'Choose whether you are requesting an embargo before continuing.', flash[:alert]
    end

    should 'render the embargo step and gate later steps until selection is made' do
      thesis = create(:thesis, student: @student, embargo_selection: :undecided)
      create(:document, thesis_id: thesis.id, user_id: @student.id, supplemental: false,
                        file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_EMBARGO }
      assert_response :success
      assert_template 'embargo'

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_REVIEW }
      assert_response :success
      assert_template 'embargo'
      assert_equal 'Choose whether you are requesting an embargo before continuing.', flash[:alert]
    end

    should 'preserve review access for a closed thesis with an undecided embargo selection' do
      thesis = create(:thesis, student: @student, status: Thesis::UNDER_REVIEW, embargo_selection: :undecided)
      create(:document, thesis_id: thesis.id, user_id: @student.id, supplemental: false,
                        file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_REVIEW }

      assert_response :success
      assert_template 'review'
    end

    should 'render embargo for a closed thesis draft extension' do
      thesis = create(:thesis, student: @student, status: Thesis::UNDER_REVIEW, embargo_selection: :requested)
      create(:embargo_request, thesis: thesis, status: :approved)
      extension = create(:embargo_request, thesis: thesis, request_type: :extension, status: :draft)

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_EMBARGO }

      assert_response :success
      assert_template 'embargo'
      assert_equal extension, assigns(:embargo_request)
      assert_includes response.body, 'Embargo request draft'
    end

    should 'show no-request state before a retained draft and mark the active progress step' do
      thesis = create(:thesis, student: @student, embargo_selection: :not_requested)
      create(:embargo_request, thesis: thesis, status: :draft)

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_EMBARGO }

      assert_response :success
      assert_includes response.body, 'No embargo request has been selected.'
      refute_includes response.body, 'Embargo request draft</h3>'
      assert_includes response.body, 'aria-current="step"'
      assert_operator response.body.index('title="Upload Files"'), :<, response.body.index('title="Embargo request"')
      assert_operator response.body.index('title="Embargo request"'), :<, response.body.index('title="Review licences"')
    end

    should 'load thesis object and display or redirect to proper process step' do
      thesis = create(:thesis, student: @student, embargo_selection: :not_requested)
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

    should 'show the submitted embargo summary on the final submission step' do
      thesis = create(:thesis, student: @student, embargo_selection: :requested)
      request = create(:submitted_embargo_request, thesis: thesis)
      request.update!(submitted_at: Time.zone.parse('2026-07-28 10:00:00'))
      document = create(:document, thesis: thesis, user: @student, embargo_request: request, usage: :embargo,
                                   supplemental: true, file: fixture_file_upload('pdf-document.pdf'))
      create_primary_document(thesis)

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_SUBMIT }

      assert_response :success
      assert_equal request, assigns(:embargo_request)
      assert_includes response.body, 'Pending staff review'
      assert_includes response.body, request.reason_label
      assert_includes response.body, '12 months'
      assert_includes response.body, document.name
      refute_includes response.body, student_thesis_document_path(@student, thesis, document)
      assert_includes response.body, 'Review embargo request'
    end

    should 'show a pending embargo outcome on status' do
      thesis = create(:thesis, student: @student, status: Thesis::UNDER_REVIEW, embargo_selection: :requested)
      request = create(:submitted_embargo_request, thesis: thesis)
      request.update!(submitted_at: Time.zone.parse('2026-07-28 10:00:00'))
      create_primary_document(thesis)

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_STATUS }

      assert_response :success
      assert_includes response.body, 'Pending staff review'
      assert_includes response.body, 'July 28, 2026'
    end

    should 'show an active approved embargo and extension action when no request is open' do
      thesis = create(:thesis, student: @student, status: Thesis::UNDER_REVIEW, embargo_selection: :requested)
      create(:embargo_request, thesis: thesis, status: :approved, approved_until: Date.new(2027, 7, 28))
      create_primary_document(thesis)

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_STATUS }

      assert_response :success
      assert_includes response.body, 'Approved until July 28, 2027'
      assert_includes response.body, 'Request an extension'
    end

    should 'show an expired approved embargo outcome' do
      thesis = create(:thesis, student: @student, status: Thesis::UNDER_REVIEW, embargo_selection: :requested)
      create(:embargo_request, thesis: thesis, status: :approved, approved_until: Date.new(2026, 7, 27))
      create_primary_document(thesis)

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_STATUS }

      assert_response :success
      assert_includes response.body, 'Embargo expired on July 27, 2026'
    end

    should 'show a declined embargo outcome with escaped decision notes' do
      thesis = create(:thesis, student: @student, status: Thesis::UNDER_REVIEW, embargo_selection: :requested)
      create(:embargo_request, thesis: thesis, status: :declined, decision_notes: '<script>alert(1)</script>')
      create_primary_document(thesis)

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_STATUS }

      assert_response :success
      assert_includes response.body, 'Declined'
      assert_includes response.body, '&lt;script&gt;alert(1)&lt;/script&gt;'
      refute_includes response.body, '<script>alert(1)</script>'
    end

    should 'show no-request status and suppress an extension action when an open request exists' do
      no_request_thesis = create(:thesis, student: @student, status: Thesis::UNDER_REVIEW, embargo_selection: :not_requested)
      create_primary_document(no_request_thesis)

      get :thesis_process_router, params: { id: no_request_thesis.id, process_step: Thesis::PROCESS_STATUS }

      assert_includes response.body, 'No embargo requested'

      thesis = create(:thesis, student: @student, status: Thesis::UNDER_REVIEW, embargo_selection: :requested)
      create(:embargo_request, thesis: thesis, status: :approved)
      create(:embargo_request, thesis: thesis, request_type: :extension, status: :draft)
      create_primary_document(thesis)

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_STATUS }

      refute_includes response.body, 'Request an extension'
    end

    should 'allow another extension after a later declined request when an approval remains in history' do
      thesis = create(:thesis, student: @student, status: Thesis::UNDER_REVIEW, embargo_selection: :requested)
      create(:embargo_request, thesis: thesis, status: :approved)
      create(:embargo_request, thesis: thesis, request_type: :extension, status: :declined)
      create_primary_document(thesis)

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_STATUS }

      assert_includes response.body, 'Declined'
      assert_includes response.body, 'Request an extension'
    end

    should 'suppress an extension action when an approved thesis has a submitted request open' do
      thesis = create(:thesis, student: @student, status: Thesis::UNDER_REVIEW, embargo_selection: :requested)
      create(:embargo_request, thesis: thesis, status: :approved)
      create(:submitted_embargo_request, thesis: thesis)
      create_primary_document(thesis)

      get :thesis_process_router, params: { id: thesis.id, process_step: Thesis::PROCESS_STATUS }

      refute_includes response.body, 'Request an extension'
    end

    should 'not load a thesis belonging to another student' do
      thesis = create(:thesis)

      assert_raises ActiveRecord::RecordNotFound do
        get :thesis_process_router, params: { id: thesis.id, process_step: 'whatever' }
      end
    end
  end

  private

  def create_primary_document(thesis)
    create(:document, thesis: thesis, user: @student, supplemental: false,
                      file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))
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
