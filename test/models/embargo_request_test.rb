# frozen_string_literal: true

require 'test_helper'

class EmbargoRequestTest < ActiveSupport::TestCase
  should belong_to(:thesis)
  should belong_to(:decided_by).optional
  should have_many(:documents)

  test 'draft may be incomplete but submission may not' do
    request = build(:embargo_request, status: :draft, rationale: nil)

    assert request.valid?
    assert_not request.valid?(:submission)
    assert_includes request.errors[:rationale], "can't be blank"
  end

  test 'submitted request requires one active supervisor letter' do
    request = create(:embargo_request, status: :draft)

    assert_not request.submit_request
    assert_includes request.errors[:base], 'Upload a supervisor support letter before submitting the request.'
  end

  test 'incomplete submitted request cannot be persisted directly' do
    request = build(:embargo_request, status: :submitted, rationale: nil)

    assert_not request.save
    assert_includes request.errors[:rationale], "can't be blank"
  end

  test 'incomplete draft cannot be updated directly to submitted' do
    request = create(:embargo_request, rationale: nil)
    request.status = :submitted

    assert_not request.save
    assert_includes request.errors[:rationale], "can't be blank"
  end

  test 'submitted request cannot be updated to remove required information' do
    request = create(:submitted_embargo_request)

    assert_not request.update(rationale: nil)
    assert_includes request.errors[:rationale], "can't be blank"
  end

  test 'submit request persists a complete draft with an active supervisor letter' do
    request = create(:embargo_request)
    create(:document, thesis: request.thesis, user: request.thesis.student,
                      embargo_request_id: request.id, usage: :embargo_letter,
                      supplemental: true,
                      file: fixture_file_upload('pdf-document.pdf'))

    assert request.submit_request
    assert request.submitted?
    assert_not_nil request.submitted_at
  end

  test 'save persists a request without reloading a dirty associated thesis' do
    thesis = create(:thesis)
    thesis.embargo_selection = :requested
    request = build(:embargo_request, thesis: thesis)

    assert request.save
    assert thesis.changed?
    assert_equal 'requested', thesis.embargo_selection
  end

  test 'save! persists a request without reloading a dirty associated thesis' do
    thesis = create(:thesis)
    thesis.embargo_selection = :requested
    request = build(:embargo_request, thesis: thesis)

    assert request.save!
    assert thesis.changed?
    assert_equal 'requested', thesis.embargo_selection
  end

  test 'save! keeps record invalid semantics with a dirty associated thesis' do
    thesis = create(:thesis)
    thesis.embargo_selection = :requested
    request = build(:embargo_request, thesis: thesis, status: :submitted, rationale: nil)

    assert_raises(ActiveRecord::RecordInvalid) { request.save! }
    assert thesis.changed?
    assert_equal 'requested', thesis.embargo_selection
  end

  test 'extension requires a previous approved request' do
    request = create(:embargo_request, request_type: :extension)

    assert_not request.valid?(:submission)

    create(:embargo_request, thesis: request.thesis, status: :approved,
                            approved_until: 1.year.from_now.to_date,
                            decided_at: Time.current, decided_by: create(:user))
    create(:document, thesis: request.thesis, user: request.thesis.student,
                      embargo_request_id: request.id, usage: :embargo_letter,
                      supplemental: true,
                      file: fixture_file_upload('pdf-document.pdf'))

    assert request.valid?(:submission)
  end

  test 'only one draft or submitted request may be open for a thesis' do
    existing = create(:embargo_request, status: :draft)
    duplicate = build(:embargo_request, thesis: existing.thesis, status: :draft)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:base], 'This thesis already has an open embargo request.'
  end

  test 'publication blocking includes submitted and unexpired approved requests' do
    submitted = create(:submitted_embargo_request)
    approved = create(:embargo_request, status: :approved, approved_until: Date.new(2026, 7, 28))
    boundary = create(:embargo_request, status: :approved, approved_until: Date.new(2026, 7, 27))
    expired = create(:embargo_request, status: :approved, approved_until: Date.new(2026, 7, 26))
    declined = create(:embargo_request, status: :declined)

    blocking = EmbargoRequest.publication_blocking(on: Date.new(2026, 7, 27))

    assert_includes blocking, submitted
    assert_includes blocking, approved
    assert_includes blocking, boundary
    assert_not_includes blocking, expired
    assert_not_includes blocking, declined
    assert expired.expired?(on: Date.new(2026, 7, 27))
    assert_not boundary.expired?(on: Date.new(2026, 7, 27))
  end

  test 'toronto today remains on the prior date before midnight Eastern' do
    travel_to Time.utc(2026, 7, 28, 3, 59, 59) do
      assert_equal Date.new(2026, 7, 27), EmbargoRequest.toronto_today
    end
  end

  test 'approval uses the Toronto decision date and accepts only the allowed 36 month window' do
    request = create(:submitted_embargo_request)
    staff = create(:user, role: User::STAFF)

    assert_not request.approve(decided_by: staff, approved_until: EmbargoRequest.toronto_today - 1.day)
    assert request.submitted?
    assert_not request.approve(decided_by: staff,
                               approved_until: EmbargoRequest.toronto_today + 3.years + 1.day)
    assert request.submitted?
    assert request.approve(decided_by: staff,
                           approved_until: EmbargoRequest.toronto_today + 3.years)
    assert request.approved?
  end

  test 'approval requires an approver and a date' do
    request = create(:submitted_embargo_request)

    assert_not request.approve(decided_by: nil, approved_until: EmbargoRequest.toronto_today + 1.year)
    assert_includes request.errors[:decided_by], "can't be blank"
    assert_not request.approve(decided_by: create(:user), approved_until: nil)
    assert_includes request.errors[:approved_until], "can't be blank"
    assert request.submitted?
  end

  test 'decline requires decision notes' do
    request = create(:submitted_embargo_request)

    assert_not request.decline(decided_by: create(:user), decision_notes: '  ')
    assert_includes request.errors[:decision_notes], "can't be blank"
    assert request.submitted?
  end

  test 'an invalid decision can be retried on the same record instance' do
    request = create(:submitted_embargo_request)
    staff = create(:user)

    assert_not request.approve(decided_by: staff, approved_until: EmbargoRequest.toronto_today + 3.years + 1.day)
    assert_not request.changed?
    assert request.approve(decided_by: staff, approved_until: EmbargoRequest.toronto_today + 1.year)
    assert request.reload.approved?
  end

  test 'a second decision cannot overwrite the first' do
    request = create(:submitted_embargo_request)
    first = create(:user, role: User::STAFF)
    second = create(:user, role: User::STAFF)

    assert request.approve(decided_by: first, approved_until: EmbargoRequest.toronto_today + 1.year)
    assert_not request.decline(decided_by: second, decision_notes: 'Late second decision')
    assert_equal first, request.reload.decided_by
    assert request.approved?
  end

  test 'a stale record cannot overwrite a concurrent first decision' do
    first_request = create(:submitted_embargo_request)
    stale_request = EmbargoRequest.find(first_request.id)
    first = create(:user, role: User::STAFF)
    second = create(:user, role: User::STAFF)

    assert first_request.approve(decided_by: first, approved_until: EmbargoRequest.toronto_today + 1.year)
    assert_not stale_request.decline(decided_by: second, decision_notes: 'Stale second decision')
    assert_equal first, first_request.reload.decided_by
    assert first_request.approved?
  end

  test 'an approved or declined request cannot be edited after its decision' do
    request = create(:embargo_request, status: :approved, decided_by: create(:user),
                                       decided_at: Time.current,
                                       approved_until: EmbargoRequest.toronto_today + 1.year)

    assert_not request.update(rationale: 'Changed after a decision')
    assert_includes request.errors[:base], 'A decided embargo request cannot be changed.'
  end

  %i[approved declined].each do |terminal_status|
    %i[draft submitted].each do |open_status|
      test "a #{terminal_status} request cannot be reopened as #{open_status}" do
        decider = create(:user)
        decided_at = Time.current
        approved_until = EmbargoRequest.toronto_today + 1.year
        decision_notes = 'Original decision notes'
        request = create(:embargo_request, status: terminal_status, decided_by: decider,
                                           decided_at: decided_at, approved_until: approved_until,
                                           decision_notes: decision_notes)

        assert_not request.update(status: open_status, decided_by: create(:user), decided_at: nil,
                                  approved_until: nil, decision_notes: 'Overwritten decision notes')
        assert_includes request.errors[:base], 'A decided embargo request cannot be changed.'

        request.reload
        assert_equal terminal_status.to_s, request.status
        assert_equal decider, request.decided_by
        assert_equal decided_at.to_i, request.decided_at.to_i
        assert_equal approved_until, request.approved_until
        assert_equal decision_notes, request.decision_notes
      end
    end
  end
end
