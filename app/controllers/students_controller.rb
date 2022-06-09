class StudentsController < ApplicationController
  authorize_resource

  def gem_search
    if params[:sisid]
      @students = Student.find_by_sisid_or_name(params[:sisid])
      if @students.size > 0
        if @students.size == 1
          @student = @students.first
          redirect_to @student
        else
          @search_result = "Results for '#{params[:sisid]}' search"
          @students = @students.page(params[:page])
          render template: "students/index"
        end
      else
        records = GemRecord.find_by_sisid_or_name(params[:sisid])
        if records.size == 1
          @gem_record = records.first
          redirect_to @gem_record, notice: "This is still a Gem Record, it hasn't been converted to an ETD Record."
        else
          if records.size == 0
            redirect_to gem_records_path, alert: "Student was not found. The student must exist in the Gem database."
          else
            @search_result = "Results for '#{params[:sisid]}' search"
            @gem_records = records.page(params[:page])
            render template: "gem_records/index"
          end

        end
      end
    else
      redirect_to :back, notice: "You must provide a valid SISID"
    end
  end

  def send_invite
    @student = Student.find(params[:id])


    StudentMailer.invitation_email(@student).deliver_later
    @student.invitation_sent_at = Time.now.beginning_of_day
    @student.audit_comment =   "Sent an invitation email to #{@student.email}"
    @student.save(validate: false)

    redirect_to @student, notice: "Sent an invitation email to #{@student.name}."
  end

  def index
    @students = Student.where(nil)

    if params[:oldest]
      @students = @students.oldest
    else
      @students = @students.most_recent
    end

    @students = @students.page(params[:page])
  end

  def audit_trail
    @student = Student.find(params[:id])
    @audits = @student.audits | @student.associated_audits | @student.theses.collect { |t| t.associated_audits }.flatten
    @audits.sort! { |a, b| a.created_at <=> b.created_at }

    @audits_grouped = @audits.reverse.group_by { |a| a.created_at.at_beginning_of_day }
  end

  def show
    @student = Student.find(params[:id])

    if current_user.role == User::STUDENT
      redirect_to student_view_index_path
    end

    @current_theses = @student.theses
    gem_record_event_ids = @current_theses.collect { |t| t.gem_record_event_id }

    if gem_record_event_ids.count > 0
      @available_theses = GemRecord.where(sisid: @student.sisid).where("seqgradevent not in (?)", gem_record_event_ids)
    else
      @available_theses = GemRecord.where(sisid: @student.sisid)
    end
  end

  def new
    @student = Student.new

    if params[:sisid]

      record = GemRecord.find_by_sisid(params[:sisid])
      if record
        @student.sisid = record.sisid
        @student.username = record.sisid.to_s
        @student.name = record.studentname
        @student.email = record.emailaddress
        @student.created_by = current_user
        @student.blocked = true
        @student.role = User::STUDENT

        redirect_to @student, notice: "Converted #{@student.name} record from Gem." if @student.save

      end
    end

  end

  def create
     @student = Student.new(student_params)
     @student.created_by = current_user
     @student.blocked = false
     @student.role = User::STUDENT

     @student.audit_comment = "Registering a new student."

     if @student.save
       redirect_to @student, notice: "Successfully created student."
     else
       render :action => 'new'
     end
  end

  def edit
    @student = Student.find(params[:id])
  end

  def update
    @student = Student.find(params[:id])

    params[:student].delete(:role) # make sure student role doesnt' get reset

    @student.audit_comment = "Updating student details."

    if @student.update_attributes(student_params)
      redirect_to @student, notice: "Successfully updated student."
    else
      render :action => 'edit'
    end
  end

  def block
    @student = Student.find(params[:id])
    @student.audit_comment = "Blocking the student."
    @student.block

     redirect_to @student, notice: "Unblocked this student. Access enabled."
  end

  def unblock
    @student = Student.find(params[:id])
    @student.audit_comment = "Unblocking the student."
    @student.unblock

    redirect_to @student, notice: "Unblocked this student. Access enabled."
  end

  def destroy
     @student = Student.find(params[:id])

     if current_user.role == User::MANAGER
       @student.destroy
       redirect_to @student, alert: "Student and associated files have been removed permanently"
     else
       redirect_to @student, alert: "Only a manager can delete this student"
     end
  end

  private
  def student_params  
    params.require(:student).permit(:name, :email, :username, :sisid, :invitation_sent_at, :role)
  end
end
