# frozen_string_literal: true

class ThesisReplacedDocumentsController < ApplicationController
  def show
    student = Student.find(params[:student_id])
    thesis = student.theses.find(params[:thesis_id])
    authorize! :read, thesis
    return redirect_to(unauthorized_url) if current_user.role == User::STUDENT

    replaced_document = thesis.replaced_documents.find(params[:id])
    send_file replaced_document.file.path,
              filename: replaced_document.download_filename,
              type: replaced_document.content_type || 'application/octet-stream',
              disposition: 'attachment'
  end
end
