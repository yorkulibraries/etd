# frozen_string_literal: true

module Theses
  class EmbargoRequestsController < ApplicationController
    before_action :load_student_and_thesis

    def select
      authorize! :update, @thesis
      selection = params[:embargo_selection]
      unless %w[not_requested requested].include?(selection)
        return redirect_to embargo_step_path, alert: 'Choose whether you are requesting an embargo.'
      end

      cancellation_alert = nil
      @thesis.with_lock do
        authorize! :update, @thesis
        cancellation_alert = cancellation_alert_for(selection)
        next if cancellation_alert

        @thesis.update!(embargo_selection: selection)
        create_draft_request! if selection == 'requested'
      end

      return redirect_to embargo_step_path, alert: cancellation_alert if cancellation_alert

      redirect_to selection == 'requested' ? embargo_step_path :
                    student_view_thesis_process_path(@thesis, Thesis::PROCESS_REVIEW)
    end

    def create
      authorize! :create, @thesis.embargo_requests.build
      previous = nil
      request = nil
      saved = @thesis.with_lock do
        previous = @thesis.embargo_requests.approved.order(decided_at: :desc).first
        next false unless previous

        request = @thesis.embargo_requests.build(extension_attributes_from(previous))
        authorize! :create, request
        request.save
      end
      unless previous
        return redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_STATUS),
                           alert: 'An extension requires a previously approved embargo.'
      end

      if saved
        redirect_to embargo_step_path(anchor: 'request-form')
      else
        redirect_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_STATUS),
                    alert: request.errors.full_messages.to_sentence
      end
    end

    def update
      saved = @thesis.with_lock do
        @request = @thesis.embargo_requests.find(params[:id])
        authorize! :update, @request
        @request.update(request_params)
      end
      if saved
        redirect_to embargo_step_path(anchor: 'request-documents'), notice: 'Embargo request draft saved.'
      else
        render_embargo_step
      end
    end

    def submit
      submitted = @thesis.with_lock do
        @request = @thesis.embargo_requests.find(params[:id])
        authorize! :submit, @request
        @request.submit_request
      end
      if submitted
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

    def request_params
      params.require(:embargo_request).permit(
        :request_type, :reason, :rationale, :requested_duration_months,
        :contact_phone, :contact_email, :graduate_program_director_name,
        :graduate_program_director_email, :supervisor_name, :supervisor_email
      )
    end

    def create_draft_request!
      return if @thesis.embargo_requests.exists?

      request = @thesis.embargo_requests.build(
        request_type: :new_request,
        contact_email: default_contact_email,
        supervisor_name: @thesis.supervisor
      )
      authorize! :create, request
      request.save!
    end

    def cancellation_alert_for(selection)
      return unless selection == 'not_requested'

      if @thesis.embargo_requests.submitted.exists?
        'A submitted embargo request cannot be cancelled.'
      elsif @thesis.embargo_requests.where.not(status: EmbargoRequest.statuses[:draft]).exists?
        'An embargo request with a decision cannot be cancelled.'
      end
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
