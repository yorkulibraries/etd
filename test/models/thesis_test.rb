# frozen_string_literal: true

require 'test_helper'

class ThesisTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  should 'create a valid thesis' do
    thesis = build(:thesis, title: 'some thesis')

    assert_difference 'Thesis.count', 1 do
      thesis.save
    end
  end

  should belong_to(:student)
  should have_many(:documents).dependent(:delete_all)
  # should have_many(:documents)

  should have_many(:embargo_requests).dependent(:destroy)

  should 'complete the embargo step when no request is needed' do
    thesis = build(:thesis, embargo_selection: :not_requested)

    assert thesis.embargo_not_requested?
    assert thesis.embargo_step_complete?
  end

  should 'complete the embargo step when an approved request exists' do
    thesis = create(:thesis, embargo_selection: :requested)
    approved_request = create(:embargo_request, thesis: thesis, status: :approved)

    assert thesis.embargo_requested?
    assert thesis.embargo_step_complete?
    assert_equal approved_request, thesis.current_embargo_request
  end

  should 'require a completed embargo step before a student submits for review' do
    student = create(:student)
    thesis = build(:thesis, student: student, current_user: student, embargo_selection: :undecided,
                            loc_subjects: create_list(:loc_subject, 1))

    assert_not thesis.valid?(:submit_for_review)
    assert_includes thesis.errors[:base], 'Complete the embargo step before submitting for review.'

    thesis.embargo_selection = :not_requested
    assert thesis.valid?(:submit_for_review)
  end

  should 'require a requested embargo to leave draft before a student submits for review' do
    student = create(:student)
    thesis = create(:thesis, student: student, embargo_selection: :requested, loc_subjects: create_list(:loc_subject, 1))
    create(:embargo_request, thesis: thesis, status: :draft)
    thesis.current_user = student

    assert_not thesis.valid?(:submit_for_review)
    assert_includes thesis.errors[:base], 'Complete the embargo step before submitting for review.'
  end
  
  ## VALIDATIONS
  # Licences are required fields

  ## CERTIFY CONTENT CORRECT
  should 'validate presence of certify_content_correct if submitting_for_review_by_student?' do
    student_user = create(:student)
    thesis = build(:thesis, current_user: student_user, certify_content_correct: false)
    assert_not thesis.valid?(:submit_for_review), 'Should not validate thesis if certify_content_correct is missing for students submitting for review'
    assert_includes thesis.errors[:base], "Please check the ‘I certify that the content is correct’ button to proceed"
  end

  should 'not validate presence of certify_content_correct if not submitting_for_review_by_student?' do
    staff_user = create(:user)
    thesis = build(:thesis, current_user: staff_user, certify_content_correct: nil)
    assert thesis.valid?(:submit_for_review), 'Should validate thesis if certify_content_correct is missing for staff even when submitting for review'
  end

  should 'not validate presence of certify_content_correct if updating by student but not submitting for review' do
    student_user = create(:student)
    thesis = build(:thesis, current_user: student_user, certify_content_correct: nil, loc_subjects: create_list(:loc_subject, 1))
    assert thesis.valid?, 'Should validate thesis if certify_content_correct is missing for students when not submitting for review'
  end
  
  ## LICENCE AGREEMENTS
  should 'validate presence of lac_licence_agreement if accepting_licences by student' do
    student_user = create(:student)
    thesis = build(:thesis, current_user: student_user, lac_licence_agreement: false, yorkspace_licence_agreement: true, etd_licence_agreement: true)
    assert_not thesis.valid?(:accept_licences), 'Should not validate thesis if lac_licence_agreement is missing for students accepting licences'
    assert_includes thesis.errors[:lac_licence_agreement], "can't be blank"
  end

  should 'validate presence of yorkspace_licence_agreement if accepting_licences by student' do
    student_user = create(:student)
    thesis = build(:thesis, current_user: student_user, lac_licence_agreement: true, yorkspace_licence_agreement: false, etd_licence_agreement: true)
    assert_not thesis.valid?(:accept_licences), 'Should not validate thesis if yorkspace_licence_agreement is missing for students accepting licences'
    assert_includes thesis.errors[:yorkspace_licence_agreement], "can't be blank"
  end

  should 'validate presence of etd_licence_agreement if accepting_licences by student' do
    student_user = create(:student)
    thesis = build(:thesis, current_user: student_user, lac_licence_agreement: true, yorkspace_licence_agreement: true, etd_licence_agreement: false)
    assert_not thesis.valid?(:accept_licences), 'Should not validate thesis if etd_licence_agreement is missing for students accepting licences'
    assert_includes thesis.errors[:etd_licence_agreement], "can't be blank"
  end

  should 'not validate presence of licence agreements if not accepting_licences by student' do
    staff_user = create(:user)
    thesis = build(:thesis, current_user: staff_user, lac_licence_agreement: nil, yorkspace_licence_agreement: nil, etd_licence_agreement: nil)
    assert thesis.valid?(:accept_licences), 'Should validate thesis if licence agreements are missing for staff even when accepting licences'
  end

  should 'not validate presence of licence agreements if updating by student but not accepting licences' do
    student_user = create(:student)
    thesis = build(:thesis, current_user: student_user, lac_licence_agreement: nil, yorkspace_licence_agreement: nil, etd_licence_agreement: nil, loc_subjects: create_list(:loc_subject, 1))
    assert thesis.valid?, 'Should validate thesis if licence agreements are missing for students when not accepting licences'
  end

  should 'fail if required attributes are missing' do
    assert !build(:thesis, student_id: nil).valid?, 'Thesis must be assigned to a student'
    assert !build(:thesis, title: nil).valid?, 'Title for thesis must be present'
    assert !build(:thesis, author: nil).valid?, "Author's name must be filled in"
    assert !build(:thesis, supervisor: nil).valid?, "Supervisor's name must be present"
    assert !build(:thesis, degree_name: nil).valid?, 'Degree Name must be set'
    assert !build(:thesis, degree_level: nil).valid?, 'Degree Level should be present'
    assert !build(:thesis, program: nil).valid?, 'Program name must be present'
    assert !build(:thesis, exam_date: nil).valid?, 'Exam date is required'
    assert !build(:thesis, gem_record_event_id: nil).valid?, 'Gem Record Event ID must be present'
    assert !build(:thesis, published_date: '29302').valid?, 'Must be a valid date'
    assert !build(:thesis, exam_date: '#29302').valid?, 'Must be a valid date'
  end

  should ' be able to delete a thesis' do
    thesis = create(:thesis)

    assert_difference 'Thesis.count', -1 do
      thesis.destroy
    end
  end

  should 'prepoplate degree name and degree level based on program on create' do
    thesis = Thesis.new
    thesis.program = 'GS MA PSYC>CLDV - Faculty Of Graduate Studies, M.A., Psychology(Functional Area: Clinical-Developmental)'
    thesis.assign_degree_name_and_level

    assert_equal 'MA', thesis.degree_name
    assert_equal Thesis::MASTERS, thesis.degree_level

    thesis.program = 'GS PHD ENVS - Faculty Of Graduate Studies, Ph.D., Environmental Studies'
    thesis.assign_degree_name_and_level

    assert_equal 'PhD', thesis.degree_name
    assert_equal Thesis::DOCTORAL, thesis.degree_level

    thesis.program = 'GS MSC KAHS - Faculty Of Graduate Studies, M.Sc., Kinesiology & Health Science'
    thesis.assign_degree_name_and_level

    assert_equal 'MSc', thesis.degree_name
    assert_equal Thesis::MASTERS, thesis.degree_level
  end

  should 'delete associated documents if thesis is deleted' do
    @thesis = create(:thesis)
    create(:document, thesis: @thesis)

    assert_difference 'Document.count', -1 do
      @thesis.destroy
    end
  end

  should 'be able to update a thesis' do
    thesis = create(:thesis, title: 'Current Title')

    thesis.title = 'New Title'
    thesis.save

    assert_equal 'New Title', thesis.title, 'Title should have been updated'
  end

  should 'display only OPEN status thesis records' do
    create_list(:thesis, 5, status: Thesis::OPEN)
    create_list(:thesis, 10, status: Thesis::ACCEPTED)

    assert_equal 5, Thesis.open.count, 'There should be only OPEN status records'
  end

  should 'display only under_review status thesis records' do
    create_list(:thesis, 5, status: Thesis::OPEN)
    create_list(:thesis, 10, status: Thesis::UNDER_REVIEW)

    assert_equal 10, Thesis.under_review.count, 'There should be only UNDER_REVIEW status records'
  end

  should 'display only rejected status thesis records' do
    create_list(:thesis, 5, status: Thesis::OPEN)
    create_list(:thesis, 10, status: Thesis::REJECTED)

    assert_equal 10, Thesis.rejected.count, 'There should be only REJECTED status records'
  end

  should 'display only accepted status thesis records' do
    create_list(:thesis, 5, status: Thesis::OPEN)
    create_list(:thesis, 10, status: Thesis::ACCEPTED)

    assert_equal 10, Thesis.accepted.count, 'There should be only ACCEPTED status records'
  end

  should 'display only published status thesis records' do
    create_list(:thesis, 5, status: Thesis::OPEN)
    create_list(:thesis, 10, status: Thesis::PUBLISHED)

    assert_equal 10, Thesis.published.count, 'There should be only PUBLISHED status records'
  end

  should 'display only re_open status thesis records' do
    create_list(:thesis, 5, status: Thesis::OPEN)
    create_list(:thesis, 10, status: Thesis::RETURNED)

    assert_equal 10, Thesis.returned.count, 'There should be only RETURNED status records'
  end

  should 'paginate thesis Record lists, 20 per page by default' do
    create_list(:thesis, 40)

    records = Thesis.page(1)
    assert_equal 20, records.size
  end

  should 'create thesis subjectships' do
    create_list(:loc_subject, 10)
    thesis = create(:thesis)

    thesis.loc_subject_ids = [LocSubject.first.id, LocSubject.second.id, LocSubject.last.id]
    thesis.save

    assert_equal 3, thesis.loc_subjects.size
  end

  should 'reload thesis data from GemRecord' do
    thesis = create(:thesis, gem_record_event_id: 1234, title: 'Old Title', program: 'GS PHD PSYC>BBCS - Whatever')
    create(:gem_record, seqgradevent: 1234, title: 'New Title',
                        program: 'GS Med PSYC>BBCS - Faculty Of Graduate Studies')

    thesis.update_from_gem_record

    assert_equal 'New Title', thesis.title
    assert_equal 'GS Med PSYC>BBCS - Faculty Of Graduate Studies', thesis.program
    assert_equal 'MEd', thesis.degree_name
    assert_equal Thesis::MASTERS, thesis.degree_level

    thesis2 = create(:thesis, gem_record_event_id: 1, title: "Don't change me")
    thesis.update_from_gem_record
    assert_equal "Don't change me", thesis2.title, "Title can't change since thesis does not have a valid gem record"
  end

  ### ASSIGN TO ####
  should 'assign thesis to a user' do
    thesis = create(:thesis)
    user = create(:user)

    thesis.assign_to(user)
    thesis = Thesis.find(thesis.id)
    assert_equal user.id, thesis.assigned_to.id, 'Assigned to the user'
  end

  should 'unassign user from thesis' do
    user = create(:user)
    thesis = create(:thesis, assigned_to: user)

    thesis.unassign
    thesis = Thesis.find(thesis.id)
    assert_nil thesis.assigned_to, 'No one is assigned to the thesis'
  end

  should 'return all thesis assigned to a user' do
    user1 = create(:user)
    user2 = create(:user)

    unassigned_theses = create_list(:thesis, 2)

    user1_theses = create_list(:thesis, 3)
    user1_theses.each do |t|
      t.title = "User #{user1.id} thesis #{t.id}"
      t.save
      t.assign_to(user1) 
    end

    user2_theses = create_list(:thesis, 4)
    user2_theses.each do |t|
      t.title = "User #{user2.id} thesis #{t.id}"
      t.save
      t.assign_to(user2) 
    end
    
    assert_equal 3, Thesis.assigned_to_user(user1).count
    Thesis.assigned_to_user(user1).each do |t|
      assert_equal "User #{user1.id} thesis #{t.id}", t.title
    end

    assert_equal 4, Thesis.assigned_to_user(user2).count
    Thesis.assigned_to_user(user2).each do |t|
      assert_equal "User #{user2.id} thesis #{t.id}", t.title
    end
  end

  ## READY TO PUBLISH
  should 'return ready to publish theses' do
    create(:thesis, status: Thesis::OPEN)
    create(:thesis, status: Thesis::PUBLISHED)
    create(:thesis, status: Thesis::ACCEPTED, published_date: 1.year.from_now)
    create(:thesis, status: Thesis::ACCEPTED, published_date: 2.months.ago)
    create(:thesis, status: Thesis::ACCEPTED, published_date: 2.days.ago)

    theses = Thesis.ready_to_publish
    assert_not_nil theses, 'Should not be nil'
    assert_equal 2, theses.size, 'Should only be two'
  end

  should 'publish thesis' do
    t = create(:thesis, status: Thesis::ACCEPTED)
    t.publish

    t = Thesis.find(t.id)
    assert_equal Thesis::PUBLISHED, t.status, 'Thesis should have its status changed'
  end

  should 'not publish if thesis was embargoed' do
    t = create(:thesis, status: Thesis::ACCEPTED, embargoed: true)
    t.publish

    t = Thesis.find(t.id)
    assert_equal Thesis::ACCEPTED, t.status, 'Thesis should not have its status changed'
  end

  should 'treat a nil permanent embargo as publication blocked everywhere' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, embargoed: nil, published_date: 1.day.ago)

    assert_not_includes Thesis.publication_eligible, thesis
    assert thesis.publication_blocked?
    assert_equal 'permanent_administrative_embargo', thesis.publication_block_reason
    assert_not thesis.publish
    assert_equal Thesis::ACCEPTED, thesis.reload.status
  end

  should 'block pending requests from readiness and manual publication' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 1.day.ago)
    create(:submitted_embargo_request, thesis: thesis)

    assert_not_includes Thesis.ready_to_publish, thesis
    assert thesis.publication_blocked?
    assert_equal 'pending_embargo_request', thesis.publication_block_reason
    assert_not thesis.publish
    assert_equal Thesis::ACCEPTED, thesis.reload.status
  end

  should 'block approved requests through their Toronto approval date' do
    today = EmbargoRequest.toronto_today
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 1.day.ago)
    create(:embargo_request, thesis: thesis, status: :approved, approved_until: today,
                             decided_at: Time.current, decided_by: create(:user))

    assert thesis.publication_blocked?(on: today)
    assert_not thesis.publication_blocked?(on: today + 1.day)
  end

  should 'release declined and expired requests for publication' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 1.day.ago)
    create(:embargo_request, thesis: thesis, status: :declined,
                             decision_notes: 'Not approved', decided_at: Time.current,
                             decided_by: create(:user))
    create(:embargo_request, thesis: thesis, status: :approved,
                             approved_until: EmbargoRequest.toronto_today - 1.day,
                             decided_at: 2.years.ago, decided_by: create(:user))

    assert_not thesis.publication_blocked?
    assert_includes Thesis.ready_to_publish, thesis
  end

  should 'block a pending extension after a previous approval expires' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 1.day.ago)
    create(:embargo_request, thesis: thesis, status: :approved,
                             approved_until: EmbargoRequest.toronto_today - 1.day,
                             decided_at: 2.years.ago, decided_by: create(:user))
    create(:submitted_embargo_request, thesis: thesis, request_type: :extension)

    assert thesis.publication_blocked?
    assert_equal 'pending_embargo_request', thesis.publication_block_reason
  end

  should 'only enqueue publication email after a successful eligible publish' do
    thesis = create(:thesis, status: Thesis::ACCEPTED)

    assert_enqueued_email_with StudentMailer, :status_change_email,
                               args: [thesis.student, thesis, Thesis::ACCEPTED, Thesis::PUBLISHED] do
      assert thesis.publish
    end
    assert_equal Thesis::PUBLISHED, thesis.reload.status
  end

  should 'not enqueue publication email when the publish save fails' do
    thesis = create(:thesis, status: Thesis::ACCEPTED)
    Thesis.any_instance.stubs(:save).returns(false)

    assert_not thesis.publish
    assert_empty enqueued_jobs
    assert_equal Thesis::ACCEPTED, thesis.reload.status
  end

  should 'leave a dirty receiver unchanged when publication is blocked' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, title: 'Persisted title')
    create(:submitted_embargo_request, thesis: thesis)
    thesis.title = 'Unsaved title'

    assert_not thesis.publish
    assert_equal 'Unsaved title', thesis.title
    assert_equal Thesis::ACCEPTED, thesis.status
    assert_equal 'Persisted title', thesis.reload.title
  end

  should 'reload a dirty receiver to the published database state after a successful publication' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, title: 'Persisted title')
    thesis.title = 'Unsaved title'

    assert thesis.publish
    assert_equal Thesis::PUBLISHED, thesis.status
    assert_equal 'Persisted title', thesis.title
    assert_equal Thesis::PUBLISHED, Thesis.find(thesis.id).status
  end

  should 'leave a dirty receiver unchanged when the locked publication save fails' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, title: 'Persisted title')
    thesis.title = 'Unsaved title'
    Thesis.any_instance.stubs(:save).returns(false)

    assert_not thesis.publish
    assert_equal 'Unsaved title', thesis.title
    assert_equal Thesis::ACCEPTED, thesis.status
    assert_equal Thesis::ACCEPTED, Thesis.find(thesis.id).status
    assert_empty enqueued_jobs
  end

  should 'not show up in accepted if embargoed' do
    t = create(:thesis, status: Thesis::ACCEPTED, embargoed: false)
    create(:thesis, status: Thesis::ACCEPTED, embargoed: true)

    assert_equal 1, Thesis.accepted.size
    assert_equal t.id, Thesis.accepted.first.id
  end

  should 'not show up in published if embargoed' do
    t = create(:thesis, status: Thesis::PUBLISHED, embargoed: false)
    create(:thesis, status: Thesis::PUBLISHED, embargoed: true)

    assert_equal 1, Thesis.published.size
    assert_equal t.id, Thesis.published.first.id
  end

  should 'replace undefined characters with a ?' do
    test_string = "testing\xC2 a non UTF-8 string"
    t = Thesis.new
    t.abstract = test_string

    assert_equal 'testing� a non UTF-8 string', t.abstract
  end
end
