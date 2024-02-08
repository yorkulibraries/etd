# frozen_string_literal: true

class CommitteeMembersController < ApplicationController
  authorize_resource
  before_action do
    @student = Student.find(params[:student_id])
    @thesis = @student.theses.find(params[:thesis_id])
  end

  def new
    @committee_member = CommitteeMember.new
    respond_to do |format|
      format.html
      format.js
    end
  end

  def create
    @committee_member = CommitteeMember.new(committee_member_params)
    @committee_member.thesis = @thesis
    @committee_member.audit_comment = "Add a new committee Member, #{@committee_member.name}"

    respond_to do |format|
      if @committee_member.save
        format.html { redirect_to student_thesis_path(@student, @thesis) }
      else
        format.html { render action: 'new' }
      end

      format.js
    end
  end

  def destroy
    @committee_member = @thesis.committee_members.find(params[:id])
    @committee_member.audit_comment = "Removing a committee member #{@committee_member.name}"
    @committee_member.destroy
    respond_to do |format|
      format.html { redirect_to student_thesis_path(@student, @thesis) }
      format.js
    end
  end

  private

  def committee_member_params
    params.require(:committee_member).permit(:first_name, :last_name, :role, :thesis_id)
  end
end
