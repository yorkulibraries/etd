# frozen_string_literal: true

require 'test_helper'

class ThesisTest < ActiveSupport::TestCase
  should 'create a valid thesis' do
    thesis = build(:thesis, title: 'some thesis')

    assert_difference 'Thesis.count', 1 do
      thesis.save
    end
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
    assert_equal 'Masters', thesis.degree_level

    thesis.program = 'GS PHD ENVS - Faculty Of Graduate Studies, Ph.D., Environmental Studies'
    thesis.assign_degree_name_and_level

    assert_equal 'PhD', thesis.degree_name
    assert_equal 'Doctoral', thesis.degree_level

    thesis.program = 'GS MSC KAHS - Faculty Of Graduate Studies, M.Sc., Kinesiology & Health Science'
    thesis.assign_degree_name_and_level

    assert_equal 'MSc', thesis.degree_name
    assert_equal 'Masters', thesis.degree_level
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
    assert_equal 'Masters', thesis.degree_level

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
