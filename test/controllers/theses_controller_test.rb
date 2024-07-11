# frozen_string_literal: true

require 'test_helper'

class ThesesControllerTest < ActionController::TestCase
  should 'not be visible unless logged in' do
    get :index, params: { student_id: 123 }
    assert_redirected_to login_path
  end

  context 'as admin' do
    setup do
      @user = create(:user, role: User::ADMIN)
      @student = create(:student)
      log_user_in(@user)
    end

    should 'list all thesis' do
      create_list(:thesis, 10, student: @student)

      get :index, params: { student_id: @student.id }

      theses = assigns(:theses)

      assert theses
      assert_equal 10, theses.count

      assert_template 'index'
    end

    should 'update thesis notes' do
      thesis = create(:thesis, student: @student)

      get :show, params: { id: thesis.id, student_id: @student.id }
      t = assigns(:thesis)
      assert t

      put :update,
          params: { id: thesis.id, student_id: @student.id,
                    thesis: { notes: "Updating the thesis notes..." }
      }

      t.reload

      assert_equal "Updating the thesis notes...", t.notes, 'Notes should be updated'
    end

    should 'Show Thesis details or fail if thesis was not found' do
      thesis = create(:thesis, student: @student)

      get :show, params: { id: thesis.id, student_id: @student.id }

      t = assigns(:thesis)
      assert t
      assert_equal thesis.id, t.id, 'Should pull the right thesis'

      assert_template 'show'

      assert_raises ActiveRecord::RecordNotFound, 'Should throw a RecordNotFound' do
        get :show, params: { id: 29_292_929, student_id: @student.id }
      end
    end

    should 'load documents separately, as primary and non primary. All must be not_deleted' do
      thesis = create(:thesis, student: @student)
      create_list(:document, 1, supplemental: false, thesis:, user: @student,
                                file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))
      create_list(:document, 3, supplemental: true, thesis:, user: @student)
      create(:document, supplemental: true, deleted: true, thesis:, user: @student)
      create(:document, supplemental: false, deleted: true, thesis:, user: @student,
                        file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))

      get :show, params: { id: thesis.id, student_id: @student.id }

      primary_documents = assigns(:primary_documents)
      supplemental_documents = assigns(:supplemental_documents)
      assert primary_documents, 'Primary documents must be not nil'
      assert supplemental_documents, 'Supllemental doucments'

      assert_equal 1, primary_documents.size, '1 primary non-deleted document'
      assert_equal 3, supplemental_documents.size, '3 supplemental non-deleted documents'
    end

    should 'show new thesis form, make sure thesis author is assigned.' do
      get :new, params: { student_id: @student.id }

      thesis = assigns(:thesis)
      assert thesis, 'Make sure we get a thesis instance'
      assert_equal @student.name, thesis.author, "Author's name should be Student's name"
      assert_nil thesis.id, 'Make sure its a blank Thesis object'

      assert_template 'new'

      assert_select 'form#new_thesis', 1, 'An HTML Form should be present'
    end

    should 'prepopulate the thesis if gem record id is passed and student ids match' do
      record = create(:gem_record, sisid: @student.sisid)

      get :new, params: { gem_record: record.id, student_id: @student.id }

      thesis = assigns(:thesis)
      assert thesis, 'ensure that thesis is assigned'

      assert_equal record.title, thesis.title, 'Title should be prepopulated'
      assert_equal record.examdate.beginning_of_day, thesis.exam_date.beginning_of_day,
                   'Exam date is prepopulate with event date'
      assert_equal record.superv, thesis.supervisor, 'Supervisors must match'
      assert_equal record.program, thesis.program, 'Programs match'
    end

    should 'make sure that gem_record_event_id is saved' do
      record = create(:gem_record, sisid: @student.sisid, seqgradevent: 123)

      get :new, params: { gem_record: record.id, student_id: @student.id }

      thesis = assigns(:thesis)
      assert_equal 123, thesis.gem_record_event_id, 'Gem Record Event Id is Gem Record Event ID'

      post :create,
           params: { student_id: @student.id,
                     thesis: thesis.attributes.except('id', 'created_at', 'updated_at', 'status', 'published_date') }

      saved_thesis = assigns(:thesis)
      assert_equal 123, saved_thesis.gem_record_event_id, 'Gem Record Event ID should persist'
    end

    should "not prepopulate the thesis if gem record id is present but student ids don't match" do
      record = create(:gem_record, sisid: '999999999')

      get :new, params: { gem_record: record.id, student_id: @student.id }

      thesis = assigns(:thesis)

      assert thesis.title.blank?, 'Thesis, should be blank'
      assert thesis.supervisor.blank?, 'Supervisor should be blank'
    end

    should 'Throw an ActiveRecordNotFound exception if try to assign to a non_existent student' do
      thesis_attrs = attributes_for(:thesis)

      assert_no_difference 'Thesis.count', 'Should reject it since student has not been found' do
        assert_raises ActiveRecord::RecordNotFound do
          post :create, params: { thesis: thesis_attrs.except(:status, :published_date), student_id: 123 }
        end
      end
    end

    should 'Display edit form for an existing thesis, without student selection' do
      thesis = create(:thesis, student: @student)

      get :edit, params: { id: thesis.id, student_id: @student.id }

      assert_template 'edit', 'Edit form is visible'
      assert_select '#thesis_student', 0, 'Student selection is not visible'
    end

    should 'update loc_subjects as part of the thesis update' do
      loc_subject = create(:loc_subject)
      loc_subject2 = create(:loc_subject)
      thesis = create(:thesis, student: @student)
      put :update,
          params: { id: thesis.id, student_id: @student.id,
                    thesis: { title: 'new title', author: 'new author', status: Thesis::OPEN, loc_subject_ids: [loc_subject.id, loc_subject2.id] } }
      t = assigns(:thesis)
      assert t, 'New thesis must not be nil'
      assert_equal 2, t.loc_subjects.size, 'Two subjects assigned'
      assert_equal loc_subject.id, t.loc_subjects.first.id
      assert_equal loc_subject2.id, t.loc_subjects.last.id
    end

    should "update a valid Thesis, Student can't be changed. Status can't be changed" do
      thesis = create(:thesis, student: @student, title: 'old title', status: Thesis::UNDER_REVIEW)

      put :update,
          params: { id: thesis.id, student_id: @student.id,
                    thesis: { title: 'new title', author: 'new author', status: Thesis::OPEN } }

      assert_redirected_to student_thesis_path(@student, thesis), 'After successful update, redirect to details view'

      t = assigns(:thesis)
      assert t, 'New thesis must not be nil'
      assert_equal 'new title', t.title, 'Title should have been updated'
      assert_equal 'new author', t.author, 'Author should have been updated'
      assert_equal Thesis::UNDER_REVIEW, t.status, "Status shouldn't have changed"
      assert_equal @student.id, thesis.student.id, "Student can't be reassigned"
    end

    should 'Not update if attributes are missing' do
      thesis = create(:thesis, student: @student, title: 'old title')

      put :update, params: { id: thesis.id, student_id: @student.id, thesis: { title: '', author: 'new author' } }

      assert_response :success
      assert_template 'edit'
    end

    should 'not delete an existing thesis, instead set Status to REJECTED' do
      thesis = create(:thesis, status: Thesis::OPEN, student: @student)

      assert_no_difference 'Thesis.count' do
        delete :destroy, params: { id: thesis.id, student_id: @student.id }
      end
      assert_redirected_to student_thesis_path(@student, thesis)
      thesis = Thesis.find(thesis.id)
      assert_equal Thesis::REJECTED, thesis.status
    end

    #### STATUS CHANGE ####

    should "change status of thesis, don't allow invalid theses" do
      thesis = create(:thesis, status: Thesis::OPEN, student: @student)

      post :update_status, params: { id: thesis.id, student_id: @student.id, status: Thesis::UNDER_REVIEW }

      assert_redirected_to student_thesis_path(@student, thesis)
      thesis = Thesis.find(thesis.id)
      assert_equal Thesis::UNDER_REVIEW, thesis.status

      post :update_status, params: { id: thesis.id, student_id: @student.id, status: 'blahblabha' }
      t = assigns(:thesis)
      assert_equal Thesis::UNDER_REVIEW, t.status
    end

    should 'record dates and message for returned item' do
      thesis = create(:thesis, status: Thesis::OPEN, student: @student)

      REASON_MESSAGE = 'The thesis is missing this, and this, and so on'
      post :update_status,
           params: { id: thesis.id, student_id: @student.id, status: Thesis::RETURNED, custom_message: REASON_MESSAGE }
      thesis = assigns(:thesis)
      assert_equal thesis.returned_at, Date.today
      assert_equal thesis.status, Thesis::RETURNED
      assert_equal thesis.returned_message, REASON_MESSAGE
    end

    should 'change status of thesis, and update student record information' do
      thesis = create(:thesis, status: Thesis::OPEN, student: @student)

      post :organize_student_information,
           params: { id: thesis.id, student_id: @student.id,
                     student: { first_name: '', middle_name: '', last_name: '', email_external: '' } }
      assert_template 'student_view/process/begin'

      post :organize_student_information,
           params: { id: thesis.id, student_id: @student.id,
                     student: { first_name: 'John', middle_name: 'E', last_name: 'Cake', email_external: 'email@domain.com' } }
      assert_redirected_to student_view_thesis_process_path(thesis, Thesis::PROCESS_UPDATE)

      thesis = Thesis.find(thesis.id)
      assert_equal thesis.student.first_name, 'John'
      assert_equal thesis.student.middle_name, 'E'
      assert_equal thesis.student.last_name, 'Cake'
      assert_equal thesis.student.email_external, 'email@domain.com'
    end

    should 'record dates for each status' do
      thesis = create(:thesis, status: Thesis::OPEN, student: @student)

      post :update_status, params: { id: thesis.id, student_id: @student.id, status: Thesis::UNDER_REVIEW }
      thesis = assigns(:thesis)
      assert_equal thesis.under_review_at, Date.today

      post :update_status, params: { id: thesis.id, student_id: @student.id, status: Thesis::ACCEPTED }
      thesis = assigns(:thesis)
      assert_equal thesis.accepted_at, Date.today

      post :update_status, params: { id: thesis.id, student_id: @student.id, status: Thesis::PUBLISHED }
      thesis = assigns(:thesis)
      assert_equal thesis.published_at, Date.today
    end

    should 'send an email if notification[student] or notifcation[current_user] are present' do
      thesis = create(:thesis, status: Thesis::OPEN, student: @student)

      # enable sending of email
      AppSettings.email_status_change_allow = true
      # ActionMailer::Base.deliveries = []
      post :update_status,
           params: { id: thesis.id, student_id: @student.id, status: Thesis::UNDER_REVIEW, notify_current_user: true,
                     notify_student: true }
      # assert !ActionMailer::Base.deliveries.empty?, "Email should be sent"
      assert assigns(:email_sent), 'Set the variable'
    end

    should 'not send email if notify_student is not set' do
      thesis = create(:thesis, status: Thesis::OPEN, student: @student)

      # enable sending of email
      AppSettings.email_status_change_allow = true
      # ActionMailer::Base.deliveries = []
      post :update_status,
           params: { id: thesis.id, student_id: @student.id, status: Thesis::UNDER_REVIEW, notify_current_user: true,
                     custom_message: 'woot' }
      # assert ActionMailer::Base.deliveries.empty?, "Email should not be sent, since student is not notified"
      assert !assigns(:email_sent)
    end

    ### ASSIGN AND UNASSIGN ###
    should 'assign thesis to a user' do
      user = create(:user)
      thesis = create(:thesis, student: @student)

      post :assign, params: { id: thesis.id, student_id: @student.id, to: user.id }
      thesis = assigns(:thesis)
      assert assigns(:user), 'User object is there'
      assert_equal user.id, thesis.assigned_to.id, 'Assigned to the user'
      assert_redirected_to student_thesis_path(@student, thesis), 'Redirect back to thesis page'
    end

    should 'not assign to student users or blocked users' do
      user = create(:user, blocked: true)
      thesis = create(:thesis, student: @student)

      assert_raises ActiveRecord::RecordNotFound do
        post :assign, params: { id: thesis.id, student_id: @student.id, to: user.id }
      end

      assert_raises ActiveRecord::RecordNotFound do
        post :assign, params: { id: thesis.id, student_id: @student.id, to: @student.id }
      end
    end

    should 'unassign thesis form user' do
      thesis = create(:thesis, student: @student, assigned_to: create(:user))

      post :unassign, params: { id: thesis.id, student_id: @student.id }
      thesis = assigns(:thesis)
      assert_nil thesis.assigned_to, 'Assigned to no one now.'
      assert_redirected_to student_thesis_path(@student, thesis), 'Redirect back to thesis page'
    end
  end

  context 'as a student' do
    setup do
      @student = create(:student)
      @thesis = create(:thesis, student: @student, status: Thesis::OPEN)
      log_user_in(@student)
    end

    should 'be able to update or edit a thesis' do
      ability = Ability.new(@student)
      assert ability.can?(:edit, Thesis)
      assert ability.can?(:update, Thesis)
    end

    should 'not be able to create a new thesis or destroy it' do
      ability = Ability.new(@student)
      assert ability.cannot?(:create, Thesis)
      assert ability.cannot?(:new, Thesis)
      assert ability.cannot?(:destroy, Thesis)
    end

    should 'not be able to edit a thesis if status is not OPEN' do
      thesis = create(:thesis, student: @student, status: Thesis::UNDER_REVIEW)
      ability = Ability.new(@student)
      assert ability.cannot?(:edit, thesis)
    end

    should 'not be able to update immutable thesis fields' do
      t = create(:thesis, student: @student, status: Thesis::OPEN, title: 'old title', author: 'old author')

      # only doing two fields to test the array inclusion, if two fields work all others will

      post :update,
           params: { id: t.id, student_id: @student.id, thesis: { title: 'new title', author: 'new author' } }

      assigns(:thesis)

      # assert_not_equal "new title", thesis.title
      # assert_not_equal "new author", thesis.author
    end

    should 'not be able to update notes field in thesis' do
      put :update, params: { id: @thesis.id, student_id: @student.id, thesis: { notes: "updating thesis notes as student..." } }
      thesis = assigns(:thesis)

       assert_not_equal "updating thesis notes as student...", thesis.notes
    end

    should 'show edit for if thesis is editing, [CHECK FOR FIELDS PRESENT LATER]' do
      get :edit, params: { id: @thesis.id, student_id: @student.id }

      assert_template 'edit', 'Edit template is shown'
    end

    should 'return to student view upload process if thesis is updated' do
      put :update, params: { id: @thesis.id, student_id: @student.id, thesis: { abstract: 'woot', keywords: 'new' } }

      assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPLOAD),
                           'Should redirect to student view Upload process'
    end

    should 'show update process form if there is an error with thesis submission' do
      put :update, params: { id: @thesis.id, student_id: @student.id, thesis: { abstract: nil } }
      thesis = assigns(:thesis)
      assert_equal 1, thesis.errors.size, "There should be a one validation error, #{thesis.errors.size}"
      assert_response :success
      assert_template 'student_view/process/update'
    end

    should 'only be able to edit or update thesis if thesis status is OPEN' do
      thesis = create(:thesis, student: @student, status: Thesis::UNDER_REVIEW)
      get :edit, params: { id: thesis.id, student_id: @student.id }

      assert_redirected_to unauthorized_url

      post :update, params: { id: thesis.id, student_id: @student.id, thesis: { title: 'what' } }

      assert_redirected_to unauthorized_url
    end

    should 'submit for review, thesis status will change to under_review' do
      create(:document, supplemental: false, thesis: @thesis, user: @student,
                        file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))
      post :submit_for_review, params: { id: @thesis.id, student_id: @student.id, thesis: { certify_content_correct: true } }

      thesis = assigns(:thesis)
      assert_response :redirect
      assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_STATUS),
                           'Should redirect to student thesis process Status page'
      assert_equal Thesis::UNDER_REVIEW, thesis.status, 'Status should change'

      assert !thesis.student_accepted_terms_at.nil?, 'Ensure terms accepted date was assigned'
      assert_equal thesis.student_accepted_terms_at.beginning_of_day, Date.today.beginning_of_day,
                   'Esnure terms accepted at is today'

      assert !thesis.under_review_at.nil?, 'Ensure Under Review Dat was assigned'
      assert_equal thesis.under_review_at.beginning_of_day, Date.today.beginning_of_day,
                   'Esnure under review at is today'

      get :edit, params: { id: thesis.id, student_id: @student.id }

      assert_redirected_to unauthorized_url, 'Should redirect to unauthorized.'
    end

    should 'submit for review, thesis status will change to upload due to lack of document' do
      post :submit_for_review, params: { id: @thesis.id, student_id: @student.id, thesis: { certify_content_correct: true } }
      assigns(:thesis)
      assert_response :redirect
      assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPLOAD)
    end

    should 'should not submit for review without certifying content correct' do
      @thesis.update(certify_content_correct: false)

      post :submit_for_review, params: { id: @thesis.id, student_id: @student.id, thesis: { certify_content_correct: false } }

      assigns(:thesis)
      assert_response :redirect
      assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_SUBMIT)
      assert_equal "There was an error submitting your thesis: Certify content correct can't be blank.", flash[:alert]

    end

    ## LICENCE UPLOAD CHECK
    should "should not accept licences without a licence document" do
      # thesis = create(:thesis, student: @student)
      patch :accept_licences, params: { student_id: @student.id, id: @thesis.id, thesis: { lac_licence_agreement: true, yorkspace_licence_agreement: true, etd_licence_agreement: true } }
      assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_REVIEW)
      assert_equal 'Missing Licence Document. Please upload LAC Licence Signed Doc.', flash[:alert]
    end

    should "should accept licences with a licence document" do
      # thesis = create(:thesis, student: @student)
      # create(:document, thesis: @thesis, user: @student, usage: 'licence', supplemental: true, deleted: false)
      create(:document_licence, thesis: @thesis, user: @student, deleted: false)
      patch :accept_licences, params: { student_id: @student.id, id: @thesis.id, thesis: { lac_licence_agreement: true, yorkspace_licence_agreement: true, etd_licence_agreement: true } }
      assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_SUBMIT)
      assert_equal "Updated status to #{Thesis::STATUS_ACTIONS[@thesis.reload.status]}", flash[:notice]
    end

  end
end
