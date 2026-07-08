# frozen_string_literal: true

require 'test_helper'

class ThesisSubmissionDocumentsControllerTest < ActionController::TestCase
  context 'as staff' do
    setup do
      @staff = create(:user, role: User::STAFF)
      @student = create(:student)
      @thesis = create(:thesis, student: @student)
      @document = create(:document, supplemental: false, thesis: @thesis, user: @student,
                                    file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))
      @version = @thesis.create_submission_snapshot!(@student)
      @submission_document = @version.submission_documents.first
      log_user_in(@staff)
    end

    should 'download a submitted version document' do
      get :show, params: {
        student_id: @student.id,
        thesis_id: @thesis.id,
        submission_version_id: @version.id,
        id: @submission_document.id
      }

      assert_response :success
      assert_equal File.binread(@submission_document.file.path), @response.body
    end
  end

  context 'as student' do
    setup do
      @student = create(:student)
      @thesis = create(:thesis, student: @student)
      create(:document, supplemental: false, thesis: @thesis, user: @student,
                        file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))
      @version = @thesis.create_submission_snapshot!(@student)
      @submission_document = @version.submission_documents.first
      log_user_in(@student)
    end

    should 'not download submitted version documents from the staff view' do
      get :show, params: {
        student_id: @student.id,
        thesis_id: @thesis.id,
        submission_version_id: @version.id,
        id: @submission_document.id
      }

      assert_redirected_to unauthorized_url
    end
  end
end
