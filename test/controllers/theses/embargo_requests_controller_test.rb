# frozen_string_literal: true

require 'test_helper'

class Theses::EmbargoRequestsControllerTest < ActionController::TestCase
  tests Theses::EmbargoRequestsController

  setup do
    @student = create(:student)
    @thesis = create(:thesis, student: @student, embargo_selection: :undecided)
    log_user_in(@student)
  end

  test 'student may explicitly choose no request' do
    post :select, params: selection_params('not_requested')

    assert @thesis.reload.embargo_not_requested?
    assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_REVIEW)
  end

  test 'choosing yes creates or restores one draft' do
    assert_difference 'EmbargoRequest.count', 1 do
      post :select, params: selection_params('requested')
    end
    assert @thesis.reload.embargo_requested?

    assert_no_difference 'EmbargoRequest.count' do
      post :select, params: selection_params('requested')
    end
  end

  test 'invalid selection leaves thesis undecided' do
    post :select, params: selection_params('maybe')

    assert @thesis.reload.embargo_undecided?
    assert_equal 'Choose whether you are requesting an embargo.', flash[:alert]
  end

  test 'missing selection leaves thesis undecided with the selection prompt' do
    post :select, params: { student_id: @student.id, thesis_id: @thesis.id }

    assert @thesis.reload.embargo_undecided?
    assert_equal 'Choose whether you are requesting an embargo.', flash[:alert]
  end

  test 'student cannot access another thesis request' do
    other = create(:embargo_request)

    assert_raises ActiveRecord::RecordNotFound do
      patch :update, params: request_params_for(other, rationale: 'Changed')
    end
  end

  test 'student cannot access another students thesis' do
    other_thesis = create(:thesis)

    assert_raises ActiveRecord::RecordNotFound do
      post :select, params: { student_id: @student.id, thesis_id: other_thesis.id, embargo_selection: 'requested' }
    end
  end

  test 'student cannot cancel a submitted request by selecting no' do
    request = create(:submitted_embargo_request, thesis: @thesis)
    @thesis.update!(embargo_selection: :requested)

    post :select, params: selection_params('not_requested')

    assert @thesis.reload.embargo_requested?
    assert request.reload.submitted?
    assert_equal 'A submitted embargo request cannot be cancelled.', flash[:alert]
  end

  test 'student cannot cancel an approved request by selecting no' do
    request = create(:embargo_request, thesis: @thesis, status: :approved)
    @thesis.update!(embargo_selection: :requested)

    post :select, params: selection_params('not_requested')

    assert @thesis.reload.embargo_requested?
    assert request.reload.approved?
    assert_equal 'An embargo request with a decision cannot be cancelled.', flash[:alert]
  end

  test 'student cannot cancel a declined request by selecting no' do
    request = create(:embargo_request, thesis: @thesis, status: :declined)
    @thesis.update!(embargo_selection: :requested)

    post :select, params: selection_params('not_requested')

    assert @thesis.reload.embargo_requested?
    assert request.reload.declined?
    assert_equal 'An embargo request with a decision cannot be cancelled.', flash[:alert]
  end

  test 'draft save persists draft fields without submitting' do
    request = requested_draft

    patch :update, params: request_params_for(request, rationale: 'Saved before submission')

    assert_equal 'Saved before submission', request.reload.rationale
    assert request.draft?
    assert_equal 'Embargo request draft saved.', flash[:notice]
  end

  test 'submission renders validation errors until required letter is uploaded' do
    request = requested_draft

    post :submit, params: request_params_for(request)

    assert_response :unprocessable_entity
    assert_template 'student_view/process/embargo'
    assert request.reload.draft?
    assert_includes assigns(:request).errors.full_messages, 'Upload a supervisor support letter before submitting the request.'
    assert_includes response.body, 'href="#request-documents"'
  end

  test 'submit transitions a saved valid draft to immutable submitted request' do
    request = requested_draft
    request.update!(full_request_attributes)
    create(:document, thesis: @thesis, user: @student, embargo_request: request,
                      usage: :embargo_letter, supplemental: true,
                      file: fixture_file_upload('pdf-document.pdf'))

    post :submit, params: request_params_for(request)

    assert request.reload.submitted?
    assert_not_nil request.submitted_at
    assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_REVIEW)
  end

  test 'draft cannot submit after the student selects no embargo' do
    request = requested_draft

    post :select, params: selection_params('not_requested')
    post :submit, params: request_params_for(request)

    assert @thesis.reload.embargo_not_requested?
    assert request.reload.draft?
    assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_EMBARGO)
    assert_equal 'Select an embargo request before submitting it.', flash[:alert]
  end

  test 'submitted request cannot be updated' do
    request = create(:submitted_embargo_request, thesis: @thesis)
    @thesis.update!(embargo_selection: :requested)

    patch :update, params: request_params_for(request, rationale: 'Changed after submission')

    assert_redirected_to unauthorized_url
    assert_not_equal 'Changed after submission', request.reload.rationale
  end

  test 'student cannot create an extension without a previous approval' do
    assert_no_difference 'EmbargoRequest.count' do
      post :create, params: { student_id: @student.id, thesis_id: @thesis.id }
    end
    assert_equal 'An extension requires a previously approved embargo.', flash[:alert]
  end

  test 'student may create an extension draft for a closed thesis with an approval' do
    @thesis.update!(status: Thesis::UNDER_REVIEW, embargo_selection: :requested)
    create(:embargo_request, thesis: @thesis, status: :approved)

    assert_difference 'EmbargoRequest.count', 1 do
      post :create, params: { student_id: @student.id, thesis_id: @thesis.id }
    end

    assert @thesis.embargo_requests.order(:created_at).last.extension?
    assert_redirected_to student_view_thesis_process_path(@thesis, Thesis::PROCESS_EMBARGO, anchor: 'request-form')
  end

  test 'embargo request payload is filtered from logs' do
    assert_includes Rails.application.config.filter_parameters, :embargo_request
  end

  [User::STAFF, User::MANAGER, User::ADMIN].each do |role|
    test "#{role} can approve a submitted request" do
      staff = create(:user, role: role)
      request = create(:submitted_embargo_request)
      log_user_in(staff)

      post :approve, params: decision_params_for(request, { approved_until: EmbargoRequest.toronto_today + 1.year })

      assert request.reload.approved?
      assert_equal staff, request.decided_by
      assert_redirected_to student_thesis_path(request.thesis.student, request.thesis)
    end
  end

  test 'student cannot access staff decision actions' do
    request = create(:submitted_embargo_request, thesis: @thesis)

    post :approve, params: decision_params_for(request, { approved_until: EmbargoRequest.toronto_today + 1.year })

    assert_redirected_to unauthorized_url
    assert request.reload.submitted?
  end

  test 'staff decision actions scope request ids to their parent thesis' do
    request = create(:submitted_embargo_request)
    log_user_in(create(:user, role: User::STAFF))

    assert_raises ActiveRecord::RecordNotFound do
      post :approve, params: decision_params_for(request, { approved_until: EmbargoRequest.toronto_today + 1.year },
                                                           thesis: @thesis, student: @student)
    end
    assert request.reload.submitted?
  end

  test 'invalid approval preserves the submitted request' do
    request = create(:submitted_embargo_request)
    log_user_in(create(:user, role: User::STAFF))

    post :approve, params: decision_params_for(request, { approved_until: EmbargoRequest.toronto_today + 3.years + 1.day })

    assert request.reload.submitted?
    assert_nil request.decided_by
    assert_nil request.decided_at
    assert_nil request.approved_until
    assert_equal 'Approved until must be within 36 months of the decision date', flash[:alert]
  end

  test 'blank decline notes preserve the submitted request' do
    request = create(:submitted_embargo_request)
    log_user_in(create(:user, role: User::STAFF))

    post :decline, params: decision_params_for(request, { decision_notes: ' ' })

    assert request.reload.submitted?
    assert_nil request.decided_by
    assert_nil request.decided_at
    assert_nil request.decision_notes
    assert_equal "Decision notes can't be blank", flash[:alert]
  end

  test 'a second decision leaves the first decision fields unchanged' do
    request = create(:submitted_embargo_request)
    first = create(:user, role: User::STAFF)
    second = create(:user, role: User::STAFF)
    log_user_in(first)
    post :approve, params: decision_params_for(request, { approved_until: EmbargoRequest.toronto_today + 1.year })
    first_decided_at = request.reload.decided_at

    log_user_in(second)
    post :decline, params: decision_params_for(request, { decision_notes: 'Too late' })

    request.reload
    assert request.approved?
    assert_equal first, request.decided_by
    assert_equal first_decided_at, request.decided_at
    assert_equal EmbargoRequest.toronto_today + 1.year, request.approved_until
    assert_nil request.decision_notes
  end

  private

  def selection_params(selection)
    { student_id: @student.id, thesis_id: @thesis.id, embargo_selection: selection }
  end

  def request_params_for(request, attributes = {})
    { student_id: @student.id, thesis_id: @thesis.id, id: request.id, embargo_request: attributes }
  end

  def decision_params_for(request, attributes, thesis: request.thesis, student: request.thesis.student)
    { student_id: student.id, thesis_id: thesis.id, id: request.id, embargo_request: attributes }
  end

  def requested_draft
    post :select, params: selection_params('requested')
    @thesis.embargo_requests.draft.first
  end

  def full_request_attributes
    {
      request_type: :new_request,
      reason: :intellectual_property_contract,
      rationale: 'The sponsor agreement requires delayed publication.',
      requested_duration_months: 12,
      contact_phone: '416-555-0123',
      contact_email: 'student@example.com',
      graduate_program_director_name: 'Graduate Program Director',
      graduate_program_director_email: 'gpd@example.com',
      supervisor_name: 'Supervisor Name',
      supervisor_email: 'supervisor@example.com'
    }
  end
end
