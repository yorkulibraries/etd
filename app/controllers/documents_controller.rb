class DocumentsController < ApplicationController
  authorize_resource
  before_action :load_student_and_thesis

  def index
    @documents = @thesis.documents.not_deleted.newest
  end

  def deleted
    @documents = @thesis.documents.deleted.oldest
    @deleted_documents = true
    render 'index'
  end

  def show
    @document = @thesis.documents.find(params[:id])
  end

  def new
    @document = @thesis.documents.build
  end

  def create
    @document = @thesis.documents.new(document_params)
    @document.thesis = @thesis
    @document.user = current_user
    @document.audit_comment = "Document was uploaded. File: #{@document.name}"

    if @document.save
      if current_user.role == User::STUDENT
        redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPLOAD),
                    notice: 'Successfully created document'
      else
        redirect_to [@student, @thesis], notice: 'Successfully created document.'
      end
    else
      respond_to do |format|
        format.html { render action: 'new' }
        format.js
      end
    end
  end

  def edit
    @document = @thesis.documents.find(params[:id])
    authorize! :manage, @document
  end

  def update
    @document = @thesis.documents.find(params[:id])
    @document.audit_comment = "Document was updated. File: #{@document.name}"
    if @document.update_attributes(document_params)
      if current_user.role == User::STUDENT
        redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPLOAD),
                    notice: 'Successfully updated document'
      else
        redirect_to [@student, @thesis], notice: 'Successfully updated document.'
      end
    else
      render action: 'edit'
    end
  end

  def destroy
    @document = @thesis.documents.find(params[:id])
    @document.audit_comment = "Document was deleted. File: #{@document.name}."
    @document.destroy

    if current_user.role == User::STUDENT
      redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPLOAD),
                  notice: 'Successfully deleted the document'
    else
      redirect_to student_thesis_url(@student, @thesis), notice: 'Successfully deleted the document.'
    end
  end

  private

  def load_student_and_thesis
    @student = Student.find(params[:student_id])
    @thesis = @student.theses.find(params[:thesis_id])
  end

  def document_params
    params.require(:document).permit(:supplemental, :name, :file)
  end
end
