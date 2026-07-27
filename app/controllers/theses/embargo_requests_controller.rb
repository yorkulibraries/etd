# frozen_string_literal: true

module Theses
  class EmbargoRequestsController < ApplicationController
    before_action :load_student_and_thesis
    before_action :load_request, only: %i[update submit]

    def select
      authorize! :update, @thesis
      selection = params.require(:embargo_selection)
      unless %w[not_requested requested].include?(selection)
        return redirect_to embargo_step_path, alert: 'Choose whether you are requesting an embargo.'
      end
      if selection == 'not_requested' && @thesis.embargo_requests.submitted.exists?
        return redirect_to embargo_step_path, alert: 'A submitted embargo request cannot be cancelled.'
      end

      @thesis.with_lock do
        @thesis.update!(embargo_selection: selection)
        create_draft_request! if selection == 'requested'
      end

      redirect_to selection == 'requested' ? embargo_step_path :
                    student_view_thesis_process_path(@thesis, Thesis::PROCESS_REVIEW)
    end

    def create
      authorize! :update, @thesis
      previous = @thesis.embargo_requests.approved.order(decided_at: :desc).first
      unless previous
        return redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_STATUS),
                           alert: 'An extension requires a previously approved embargo.'
      end

      request = nil
      saved = @thesis.with_lock do
        request = @thesis.embargo_requests.build(extension_attributes_from(previous))
        authorize! :create, request
        request.save
      end
      if saved
        redirect_to embargo_step_path(anchor: 'request-form')
      else
        redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_STATUS),
                    alert: request.errors.full_messages.to_sentence
      end
    end

    def update
      authorize! :update, @request
      if @request.update(request_params)
        redirect_to embargo_step_path(anchor: 'request-documents'), notice: 'Embargo request draft saved.'
      else
        render_embargo_step
      end
    end

    def submit
      authorize! :submit, @request
      if @request.submit_request
        redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_REVIEW),
                    notice: 'Embargo request submitted for staff review.'
      else
        render_embargo_step
      end
    end

    private

    def load_student_and_thesis
      @student = Student.find(params[:student_id])
      @thesis = @student.theses.find(params[:thesis_id])
    end

    def load_request
      @request = @thesis.embargo_requests.find(params[:id])
    end

    def request_params
      params.require(:embargo_request).permit(
        :request_type, :reason, :rationale, :requested_duration_months,
        :contact_phone, :contact_email, :graduate_program_director_name,
        :graduate_program_director_email, :supervisor_name, :supervisor_email
      )
    end

    def create_draft_request!
      return if @thesis.embargo_requests.where(status: %i[draft submitted]).exists?

      request = @thesis.embargo_requests.build(
        request_type: :new_request,
        contact_email: default_contact_email,
        supervisor_name: @thesis.supervisor
      )
      authorize! :create, request
      request.save!
    end

    def extension_attributes_from(previous)
      {
        request_type: :extension,
        reason: previous.reason,
        rationale: previous.rationale,
        requested_duration_months: previous.requested_duration_months,
        contact_phone: previous.contact_phone,
        contact_email: previous.contact_email,
        graduate_program_director_name: previous.graduate_program_director_name,
        graduate_program_director_email: previous.graduate_program_director_email,
        supervisor_name: previous.supervisor_name,
        supervisor_email: previous.supervisor_email
      }
    end

    def default_contact_email
      @student.email_external.to_s.split(/[\s,]+/).first.presence || @student.email
    end

    def embargo_step_path(anchor: nil)
      student_view_thesis_process_path(@thesis, Thesis::PROCESS_EMBARGO, anchor: anchor)
    end

    def render_embargo_step
      @embargo_request = @request
      @embargo_documents = @request.documents.not_deleted
      render 'student_view/process/embargo', status: :unprocessable_entity
    end
  end
end
