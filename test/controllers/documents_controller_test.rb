# frozen_string_literal: true

require 'test_helper'

class DocumentsControllerTest < ActionController::TestCase
  context 'as admin' do
    setup do
      @user = create(:user, role: User::ADMIN)
      @student = create(:student)
      @thesis = create(:thesis, student: @student)
      log_user_in(@user)
    end

    should 'load student and thesis to view documents' do
      get :index, params: { thesis_id: @thesis.id, student_id: @student.id }

      assert assigns(:thesis)
      assert assigns(:student)
    end

    should 'not load documents from other thesis on all actions' do
      thesis = create(:thesis)
      create_list(:document, 10, thesis:)
      create_list(:document, 2, thesis: @thesis)
      document = create(:document, thesis: @thesis)

      get :index, params: { thesis_id: @thesis.id, student_id: @student.id }

      documents = assigns(:documents)
      assert_equal 3, documents.size, 'There are three documents here'

      get :show, params: { id: document.id, thesis_id: @thesis.id, student_id: @student.id }
      d = assigns(:document)
      assert_equal d.id, document.id, 'Should find the proper document'

      get :edit, params: { id: document.id, thesis_id: @thesis.id, student_id: @student.id }
      d = assigns(:document)
      assert_equal d.id, document.id, 'Should find the proper document'
    end

    should 'show all thesis documents, newest first, not deleted, from the same thesis' do
      create_list(:document, 10, deleted: true, thesis: @thesis)
      create_list(:document, 3, thesis: @thesis, created_at: 1.year.ago)
      first = create(:document, created_at: 1.day.ago, thesis: @thesis)
      create(:document, created_at: 3.years.ago, thesis: @thesis)

      get :index, params: { thesis_id: @thesis.id, student_id: @student.id }

      assert_template :index, 'Index should be its template'
      documents = assigns(:documents)
      assert documents, 'Should have a list of documents'
      assert_equal 5, documents.size, 'There are 5 documents'
      assert_equal first.id, documents.first.id, 'First is the newest'
    end

    should 'list all deleted documents for thesis' do
      create_list(:document, 3, deleted: true, thesis: @thesis)
      create_list(:document, 2, deleted: false, thesis: @thesis)

      get :deleted, params: { thesis_id: @thesis, student_id: @student }

      documents = assigns(:documents)
      assert_equal 3, documents.count, 'There are 3 deleted documents'
      assert_template 'index', 'Using index template'
      assert assigns(:deleted_documents), 'Deleted document flag is assigned'
    end

    should 'show new form' do
      get :new, params: { thesis_id: @thesis.id, student_id: @student.id }
      assert_template 'new'

      assert_select 'form.document', 1, 'The form should be there'
    end

    should 'create a new document, ensure thesis and current_user are assigned' do
      assert_difference 'Document.count' do
        post :create, params: { thesis_id: @thesis.id, student_id: @student.id,
                                document: attributes_for(:document).except(:user, :thesis) }
      end

      document = assigns(:document)

      assert_equal @user.id, document.user.id, 'Current user is the one created the document'
      assert_equal @thesis.id, document.thesis.id, 'Current thesis should be set'
      assert_redirected_to student_thesis_path(@student, @thesis), 'Should redirect to thesis details view'
    end

    should 'not allow setting of thesis and user via post create' do
      thesis = create(:thesis)
      user = create(:user)
      assert_difference 'Document.count' do
        post :create, params: { thesis_id: @thesis.id, student_id: @student.id,
                                document: attributes_for(:document, thesis:, user:) }
      end
      document = assigns(:document)

      assert_not_equal document.thesis.id, thesis.id, 'Passed thesis id should be recorded'
      assert_not_equal document.user.id, user.id, 'passed user id should not be recorded'
    end

    should 'update attachments' do
      d = create(:document, file: fixture_file_upload('document-microsoft.doc', 'application/text'),
                            thesis: @thesis)

      post :update, params: { id: d.id, thesis_id: @thesis.id, student_id: @student.id,
                              document: { file: fixture_file_upload('html-document.html', 'text/html') } }
      document = assigns(:document)
      
      assert_not_equal document.file.url, d.file.url, 'Urls should not match'
      assert_redirected_to student_thesis_path(@student, @thesis), 'Should redirect to thesis details'
    end

    should 'not delete files' do
      d = create(:document, thesis: @thesis)

      assert_no_difference 'Document.count' do
        post :destroy, params: { id: d.id, thesis_id: @thesis.id, student_id: @student.id }
      end

      assert_redirected_to student_thesis_path(@student, @thesis), 'Should redirect back to the thesis details'
      assert_equal 'Successfully deleted the document.', flash[:notice]
    end
  end

  context 'as student' do
    setup do
      @student = create(:student)
      @thesis = create(:thesis, student: @student)
      log_user_in(@student)
    end

    should 'be able to manage documents (ADD FOR HIS THESIS ONLY LATER)' do
      ability = Ability.new(@student)
      assert ability.can?(:manage, Document)
    end

    should 'not be able to edit or delete documents if thesis is not open' do
      document = create(:document, thesis: create(:thesis, student: @student, status: Thesis::UNDER_REVIEW))
      ability = Ability.new(@student)
      assert ability.cannot?(:manage, document)
    end

    should 'not be able to got the new, edit, update or delete pages' do
      @thesis = create(:thesis, student: @student, status: Thesis::UNDER_REVIEW)
      document = create(:document, thesis: @thesis)

      get :edit, params: { thesis_id: @thesis.id, id: document.id, student_id: @student.id }
      assert_redirected_to unauthorized_url

      get :new, params: { thesis_id: @thesis.id, student_id: @student.id }
      assert_redirected_to unauthorized_url

      post :update,
           params: { thesis_id: @thesis.id, student_id: @student.id, id: document.id,
                     document: { file: fixture_file_upload('html-document.html', 'text/html') } }
      assert_redirected_to unauthorized_url
    end

    should 'be able to upload another primary file if there is a primary file' do
      create(:document_for_naming, file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'),
                                   thesis: @thesis, supplemental: false)
      assert_no_difference 'Document.count' do
        post :create, params: { thesis_id: @thesis.id, student_id: @student.id,
                                document: attributes_for(:document, supplemental: false, file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf')).except(:user, :thesis) }
        document = assigns(:document)
        assert_equal 1, document.errors.size, "There should be an error coming back, #{document.errors.inspect}"
      end
    end

    should 'upload file and redirect to student thesis view' do
      assert_difference 'Document.count' do
        post :create, params: { thesis_id: @thesis.id, student_id: @student.id,
                                document: attributes_for(:document).except(:user, :thesis) }
      end

      document = assigns(:document)

      assert_equal @student.id, document.user.id, 'Current student is the one created the document'
      assert_equal @thesis.id, document.thesis.id, 'Current thesis should be set'
      assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPLOAD),
                           'Should redirect to student view upload process path'
    end

    should 'update file and redirect to student thesis view' do
      d = create(:document, file: fixture_file_upload('document-microsoft.doc', 'application/text'),
                            thesis: @thesis)
      post :update, params: { id: d.id, thesis_id: @thesis.id, student_id: @student.id,
                              document: { file: fixture_file_upload('html-document.html', 'text/html') } }

      assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPLOAD),
                           'Should redirect to student view upload process path'
    end

    should 'destroy file and redirect to studet thesis view' do
      d = create(:document, file: fixture_file_upload('document-microsoft.doc', 'application/text'),
                            thesis: @thesis)
      post :destroy, params: { id: d.id, thesis_id: @thesis.id, student_id: @student.id }

      assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPLOAD),
                           'Should redirect to student  view upload process path'
    end
  end
end
