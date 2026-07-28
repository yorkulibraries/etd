# frozen_string_literal: true

class DocumentsController < ApplicationController
  authorize_resource except: %i[new create edit update destroy download]
  before_action :load_student_and_thesis

  def index
    authorize! :show, @thesis
    @documents = @thesis.documents.not_deleted.newest
  end

  def deleted
    authorize! :show, @thesis
    @documents = @thesis.documents.deleted.oldest
    @deleted_documents = true
    render 'index'
  end

  def show
    @document = @thesis.documents.find(params[:id])
  end

  def new
    @document = @thesis.documents.build
    @document.usage = params[:usage]
    @document.supplemental = params[:supplemental]
    @document.thesis = @thesis
    @document.user = @thesis.student
    @document.embargo_request = request_from_parent(params[:embargo_request_id])
    authorize! :manage, @document
  end

  def create
    attributes = document_params.except(:embargo_request_id)
    uploaded_file = attributes.delete(:file)
    @document = @thesis.documents.new(attributes)
    @document.thesis = @thesis
    @document.user = @thesis.student
    @document.embargo_request = request_from_parent(document_params[:embargo_request_id])
    authorize! :manage, @document
    @document.file = uploaded_file

    if @document.save
      @document.name = File.basename(@document.file.path)
      @document.audit_comment = "Document was uploaded. File: #{@document.name} | #{@document.usage} | "
      @document.save
      redirect_to document_return_path(@document), notice: 'File uploaded.'
    else
      respond_to do |format|
        format.html { render action: 'new', status: :unprocessable_entity }
        format.js
      end
    end
  end

  def edit
    @document = @thesis.documents.find(params[:id])
    verify_document_request_thesis!
    authorize! :manage, @document
  end

  def update
    @document = @thesis.documents.find(params[:id])
    verify_document_request_thesis!
    authorize! :manage, @document
    @document.audit_comment = "Document was updated. File: #{@document.name}"
    if @document.update(document_params.except(:embargo_request_id))
      redirect_to document_return_path(@document), notice: 'File uploaded.'
    else
      render action: 'edit'
    end
  end

  def destroy
    @document = @thesis.documents.find(params[:id])
    verify_document_request_thesis!
    authorize! :manage, @document
    @document.audit_comment = "Document was deleted. File: #{@document.name}."
    @document.destroy
    redirect_to document_return_path(@document), notice: 'File deleted.'
  end

  def download
    @document = @thesis.documents.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @document.embargo_request_document?

    verify_document_request_thesis!
    authorize! :read, @document
    send_file @document.file.path, filename: @document.name, disposition: 'attachment'
  end

  private

  def load_student_and_thesis
    @student = Student.find(params[:student_id])
    @thesis = @student.theses.find(params[:thesis_id])
  end

  def document_params
    params.require(:document).permit(:supplemental, :name, :file, :usage, :embargo_request_id)
  end

  def request_from_parent(request_id)
    return if request_id.blank?

    request = @thesis.embargo_requests.find(request_id)
    authorize! :read, request
    request
  end

  def verify_document_request_thesis!
    return unless @document.embargo_request_document?
    return if @document.embargo_request.thesis_id == @thesis.id

    raise ActiveRecord::RecordNotFound
  end

  def document_return_path(document)
    if current_user.role == User::STUDENT && document.embargo_request_document?
      student_view_thesis_process_path(@thesis, Thesis::PROCESS_EMBARGO, anchor: 'request-documents')
    elsif current_user.role == User::STUDENT && document.usage == 'licence'
      student_view_thesis_process_path(@thesis, Thesis::PROCESS_REVIEW)
    elsif current_user.role == User::STUDENT
      student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPLOAD)
    else
      student_thesis_path(@student, @thesis)
    end
  end
end
