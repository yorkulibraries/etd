# frozen_string_literal: true

class ThesisSubmissionDocumentsController < ApplicationController
  before_action :load_submission_document

  def show
    send_file @submission_document.file.path,
              filename: @submission_document.display_name,
              type: @submission_document.content_type || 'application/octet-stream',
              disposition: 'attachment'
  end

  private

  def load_submission_document
    @student = Student.find(params[:student_id])
    @thesis = @student.theses.find(params[:thesis_id])
    authorize! :read, @thesis

    if current_user.role == User::STUDENT
      redirect_to unauthorized_url
      return
    end

    @submission_version = @thesis.submission_versions.find(params[:submission_version_id])
    @submission_document = @submission_version.submission_documents.find(params[:id])
  end
end
