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
end
