# frozen_string_literal: true

require 'test_helper'

class ThesisInvitationTest < ActiveSupport::TestCase
  should 'issue an invitation for a GEM record before its thesis exists' do
    student = create(:student)
    gem_record = create(:gem_record, sisid: student.sisid)

    assert_respond_to ThesisInvitation, :issue!
    invitation = ThesisInvitation.issue!(student:, gem_record:, sent_at: Time.current)

    assert_equal student, invitation.student
    assert_equal gem_record, invitation.gem_record
    assert_nil invitation.thesis
  end

  should 'attach a pending GEM invitation when its thesis is created' do
    student = create(:student)
    gem_record = create(:gem_record, sisid: student.sisid)
    invitation = ThesisInvitation.issue!(student:, gem_record:)

    thesis = create(:thesis, student:, gem_record_event_id: gem_record.seqgradevent)

    assert_equal thesis, invitation.reload.thesis
  end

  should 'keep deadlines and resends independent for each student ETD' do
    student = create(:student)
    first_record = create(:gem_record, sisid: student.sisid)
    second_record = create(:gem_record, sisid: student.sisid)
    ThesisInvitation.issue!(student:, gem_record: first_record, sent_at: 20.days.ago)
    ThesisInvitation.issue!(student:, gem_record: second_record, sent_at: Time.current)
    first_thesis = create(:thesis, student:, gem_record_event_id: first_record.seqgradevent)
    second_thesis = create(:thesis, student:, gem_record_event_id: second_record.seqgradevent)

    assert_not first_thesis.invitation_accessible?
    assert second_thesis.invitation_accessible?

    first_thesis.send_invitation!

    assert first_thesis.invitation_accessible?
    assert_equal 2, first_thesis.invitations.count
    assert_equal 1, second_thesis.invitations.count
  end
end
