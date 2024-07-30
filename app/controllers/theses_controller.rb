# frozen_string_literal: true

class ThesesController < ApplicationController
  load_and_authorize_resource :student
  authorize_resource :thesis, through: :student

  def organize_student_information
    @thesis = Thesis.find(params[:id])
    @student = @thesis.student
    @student.validate_secondary_info = true
    if @student.update(student_params)
      redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPDATE)
    else
      render 'student_view/process/begin'
    end
  end

  def index
    @theses = @student.theses
  end

  def show
    @thesis = @student.theses.find(params[:id])

    @primary_documents = @thesis.documents.not_deleted.primary
    @supplemental_documents = @thesis.documents.not_deleted.supplemental
    @licence_documents = @thesis.documents.not_deleted.licence
    @embargo_documents = @thesis.documents.not_deleted.embargo

    authorize! :edit, @thesis
  end

  def new
    @thesis = Thesis.new

    @thesis.author = @student.name
    @thesis.published_date = 1.year.from_now
    return unless params[:gem_record]

    record = GemRecord.find(params[:gem_record])

    return unless record && record.sisid.to_i == @student.sisid.to_i

    @thesis.title = record.title
    @thesis.gem_record_event_id = record.seqgradevent
    @thesis.supervisor = record.superv
    @thesis.exam_date = record.examdate
    @thesis.program = record.program
    @thesis.assign_degree_name_and_level
    @thesis.committee_members = record.committee_members

  end

  def create
    @thesis = Thesis.new(thesis_params)

    @thesis.student = @student
    @thesis.audit_comment = 'Starting a new thesis. Status: OPEN.'

    @thesis.audit_comment = 'Starting a new thesis. Status: OPEN.'

    @thesis.status = Thesis::OPEN
    if @thesis.save
      if params[:committee_member_ids].present?
        params[:committee_member_ids].each do |committee_member_id|
          if committee_member_id.present?
            committee_member = CommitteeMember.find(committee_member_id)
            committee_member.update(thesis: @thesis)
          end
        end
      end
      redirect_to [@student, @thesis], notice: 'ETD record successfully created.'
    else
      render action: 'new'
    end
  end

  def edit
    @thesis =  @student.theses.find(params[:id])
    authorize! :edit, @thesis
  end

  def update
    @thesis =  @student.theses.find(params[:id])

    @thesis.current_user = current_user # set the current_user for later validation

    # puts "Thesis before update: #{@thesis.pretty_inspect}"
    authorize! :update, @thesis

    @thesis.audit_comment = 'Updating thesis details.'

    if current_user.role == User::STUDENT
      if thesis_params.key?(:notes) && !thesis_params[:notes].blank?
        redirect_to [@student, @thesis], alert: 'You cannot edit thesis notes' and return
      end
    end    
    # params[:thesis] = params[:thesis].reject { |p| Student::IMMUTABLE_THESIS_FIELDS.include?(p) } if current_user.role == User::STUDENT
    ## Need to check if thesis params are empty or not, if they are -> don't update
    if @thesis.update(thesis_params)

      # puts "Thesis after update: #{@thesis.pretty_inspect}"
      if current_user.role == User::STUDENT
        redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPLOAD)
      else
        redirect_to [@student, @thesis], notice: 'Successfully updated thesis.'
      end
    elsif current_user.role == User::STUDENT

      @student = current_user
      render template: 'student_view/process/update'
    else
      render action: 'edit'

    end
  end

  def destroy
    @thesis = @student.theses.find(params[:id])
    @thesis.status = Thesis::REJECTED
    @thesis.audit_comment = 'Rejecting the thesis.'
    @thesis.save
    redirect_to student_thesis_path(@student, @thesis), notice: 'Successfully rejected thesis.'
  end

  ### STATUS UPDATES ####

  def update_status
    @thesis = @student.theses.find(params[:id])

    if params[:status] && Thesis::STATUSES.include?(params[:status])

      @thesis.audit_comment = "Updating status from #{@thesis.status} to #{params[:status]}"
      old_status = @thesis.status

      @thesis.update_attribute(:status, params[:status])
      @message = "Updated status to #{Thesis::STATUS_ACTIONS[@thesis.status]}"

      @thesis.update_attribute(:under_review_at, Date.today) if params[:status] == Thesis::UNDER_REVIEW
      @thesis.update_attribute(:accepted_at, Date.today) if params[:status] == Thesis::ACCEPTED
      if params[:status] == Thesis::RETURNED
        @thesis.update(returned_at: Date.today,
                       returned_message: params[:custom_message])
      end
      @thesis.update_attribute(:published_at, Date.today) if params[:status] == Thesis::PUBLISHED

      if params[:notify_student].blank? == false
        additional_recipients = params[:notify_current_user] ? [current_user.email] : []
        custom_message ||= params[:custom_message]

        StudentMailer.status_change_email(@student, @thesis, old_status, @thesis.status, additional_recipients,
                                          custom_message).deliver_later
        additional_recipients << @student.email
        @email_sent = "Sent to #{additional_recipients.join(', ')}"
      end

    else
      @message = 'Status was not updated'
    end

    redirect_to [@student, @thesis], notice: @message
  end

  def validate_active_thesis(thesis_id)
    Document.exists?(deleted: false, user_id: current_user.id, thesis_id:, supplemental: false)
  end

  def submit_for_review
    @thesis = @student.theses.find(params[:id])
    @thesis.current_user = current_user

    # Temporarily assign the attributes for validation
    @thesis.assign_attributes(thesis_params)

    if @thesis.valid?(:submit_for_review)
      if @thesis.update(thesis_params)
        if validate_active_thesis(@thesis.id)
          @thesis.update(audit_comment: 'Submitting for review.', student_accepted_terms_at: Date.today, under_review_at: Date.today, status: Thesis::UNDER_REVIEW)
          redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_STATUS), notice: "Updated status to #{Thesis::STATUS_ACTIONS[@thesis.status]}"
        else
          redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_UPLOAD), alert: 'Missing Primary Document'
        end
      else
        error_messages = @thesis.errors.full_messages.join(', ')
        redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_SUBMIT), alert: "There was an error submitting your thesis: #{error_messages}."
      end
    else
      error_messages = @thesis.errors.full_messages.join(', ')
      redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_SUBMIT), alert: "There was an error submitting your thesis: #{error_messages}."
    end
  end

  def validate_licence_uplaod(thesis_id)
    Document.exists?(deleted: false, user_id: current_user.id, thesis_id:, supplemental: true, usage: :licence)
  end

  def accept_licences
    @thesis = @student.theses.find(params[:id])
    @thesis.current_user = current_user

    # Temporarily assign the attributes for validation
    @thesis.assign_attributes(thesis_params)
    @thesis.pretty_inspect

    if @thesis.valid?(:accept_licences)

      if @thesis.update(thesis_params)

        if validate_licence_uplaod(@thesis.id)

          redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_SUBMIT), notice: "Updated status to #{Thesis::STATUS_ACTIONS[@thesis.status]}"
        else

          redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_REVIEW), alert: 'Missing Licence Document. Please upload LAC Licence Signed Doc.'
        end
      else

        error_messages = @thesis.errors.full_messages.join(', ')
        redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_REVIEW), alert: "There was an error submitting your thesis: #{error_messages}."
      end
    else

      error_messages = @thesis.errors.full_messages.join(', ')
      redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_REVIEW), alert: "There was an error submitting your thesis: #{error_messages}."
    end

  end

  ### THESIS ASSIGNMENT TO USERS ###
  def assign
    @thesis = @student.theses.find(params[:id])
    @user = User.active.not_students.find(params[:to])

    @thesis.audit_comment = "Assigning to #{@user.name}, by #{current_user.name}" unless @user.nil?
    @thesis.assign_to(@user)
    respond_to do |format|
      format.html { redirect_to student_thesis_path(@student, @thesis) }
      format.js
    end
  end

  def unassign
    @thesis = @student.theses.find(params[:id])
    @thesis.audit_comment = "#{current_user.name} has unassigned this thesis."
    @thesis.unassign
    respond_to do |format|
      format.html { redirect_to student_thesis_path(@student, @thesis) }
      format.js
    end
  end

  private

  def student_params
    params.require(:student).permit(:name, :first_name, :middle_name, :last_name, :email_external)
  end

  def thesis_params
    params.require(:thesis).permit(:title, :gem_record_event_id, :author, :supervisor, :student,
                                   :keywords, :embargo, :language, :degree_name, :degree_level, :program, :published_date,
                                   :exam_date, :student_id, :committee, :abstract, :assigned_to_id, :assigned_to,
                                   :student_accepted_terms_at, :under_review_at, :accepted_at, :published_at, :returned_at,
                                   :committee_members_attributes, :embargoed, :certify_content_correct, :lac_licence_agreement,
                                   :yorkspace_licence_agreement, :etd_licence_agreement, :notes,
                                   committee_members_attributes: %i[first_name last_name role id _destroy],
                                   loc_subject_ids: [])
  end
end
