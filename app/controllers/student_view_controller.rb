# frozen_string_literal: true

class StudentViewController < ApplicationController
  before_action :authorize_controller, :load_student, except: :login_as_student

  def validate_active_thesis
    Document.exists?(deleted: false, user_id: current_user.id, thesis_id: params[:id], supplemental: false)
  end

  def render_according_to_validation(template)
    if validate_active_thesis
      render(template:)
    else
      flash[:error] = 'Please upload a Primary Thesis File.'
      render template: 'student_view/process/upload'
    end
  end

  def index
    if @student.theses.count == 1
      @thesis = @student.theses.first
      redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_BEGIN)
    else
      @theses = @student.theses
    end
  end

  def thesis_process_router
    @which = params[:process_step]
    @thesis = @student.theses.find(params[:id])
    @thesis.current_user = current_user

    if (@thesis.status != Thesis::OPEN && @thesis.status != Thesis::RETURNED) && @which != Thesis::PROCESS_REVIEW &&
       !closed_extension_draft_embargo_step?
      @which = Thesis::PROCESS_STATUS
    end

    if [Thesis::OPEN, Thesis::RETURNED].include?(@thesis.status) &&
       [Thesis::PROCESS_REVIEW, Thesis::PROCESS_SUBMIT].include?(@which) && @thesis.embargo_undecided?
      @which = Thesis::PROCESS_EMBARGO
      flash.now[:alert] = 'Choose whether you are requesting an embargo before continuing.'
    end

    case @which
    when Thesis::PROCESS_BEGIN
      render template: 'student_view/process/begin'
    when Thesis::PROCESS_UPDATE
      render template: 'student_view/process/update'
    when Thesis::PROCESS_UPLOAD
      @primary_documents = @thesis.documents.not_deleted.primary
      @supplemental_documents = @thesis.documents.not_deleted.supplemental
      render template: 'student_view/process/upload'
    when Thesis::PROCESS_EMBARGO
      @embargo_request = @thesis.current_embargo_request
      @embargo_documents = @embargo_request&.documents&.not_deleted || Document.none
      render template: 'student_view/process/embargo'
    when Thesis::PROCESS_REVIEW
      @primary_documents = @thesis.documents.not_deleted.primary
      @supplemental_documents = @thesis.documents.not_deleted.supplemental
      @licence_documents = @thesis.documents.not_deleted.licence
      render_according_to_validation('student_view/process/review')
    when Thesis::PROCESS_SUBMIT
      @primary_documents = @thesis.documents.not_deleted.primary
      @supplemental_documents = @thesis.documents.not_deleted.supplemental
      @licence_documents = @thesis.documents.not_deleted.licence
      @embargo_request = @thesis.current_embargo_request
      @embargo_documents = @embargo_request&.documents&.not_deleted || Document.none
      render_according_to_validation('student_view/process/submit')
    when Thesis::PROCESS_STATUS
      @embargo_request = @thesis.current_embargo_request
      @embargo_has_open_request = @thesis.embargo_requests.where(status: %i[draft submitted]).exists?
      render_according_to_validation('student_view/process/status')
    else
      render template: 'student_view/process/status'
    end
  end

  def details
    @student = current_user
  end

  def login_as_student
    authorize! :login_as, :student

    @student = Student.find_by_id(params[:id])
    if @student
      # ensure that we can get back to whatever we were before
      session[:return_to_user_id] = current_user.id
      # then sign in as student
      session[:user_id] = @student.id

      current_user.audit_comment = "Logging in as #{@student.name}"
      current_user.save(validate: false)

      @student.audit_comment = "#{current_user.name} logged in as this student"
      @student.save(validate: false)

      redirect_to student_view_index_path
    else
      redirect_to students_path, alert: 'No such student found'
    end
  end

  def logout_as_student
    student_id = current_user.id
    session[:terms_accepted] = nil
    session[:user_id] = session[:return_to_user_id]
    session[:return_to_user_id] = nil
    redirect_to student_path(student_id)
  end

  private

  def authorize_controller
    authorize! :show, :student
  end

  def load_student
    @student = Student.find(current_user.id)
  end

  def closed_extension_draft_embargo_step?
    return false unless @which == Thesis::PROCESS_EMBARGO

    request = @thesis.current_embargo_request
    request&.draft? && request.extension?
  end
end
