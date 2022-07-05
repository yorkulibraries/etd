class Theses::EmbargoController < ApplicationController
  authorize_resource Thesis
  before_action :load_student_and_thesis

  def create
    @thesis.embargo = params[:thesis][:embargo]

    if @thesis.embargo.blank?
      @thesis.errors.add(:embargo, 'Please fill in the reason for embargo')
    else

      @thesis.embargoed = true
      @thesis.embargoed_by = current_user
      @thesis.embargoed_at = Date.today
      @thesis.published_at = 500.years.from_now
      @thesis.save(validate: false)
    end

    respond_to do |format|
      format.js
      format.html { redirect_to student_thesis_path(@student, @thesis) }
    end
  end

  private

  def load_student_and_thesis
    @student = Student.find(params[:student_id])
    @thesis = @student.theses.find(params[:thesis_id])
  end
end
