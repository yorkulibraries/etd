# frozen_string_literal: true

require 'test_helper'

class AbilityTest < ActiveSupport::TestCase
  should 'deny direct thesis and document access when the student invitation expired unopened' do
    student = create(:student)
    thesis = create(:thesis, student:)
    document = create(:document, thesis:, user_id: student.id)
    thesis.invitations.create!(student:, sent_at: 15.days.ago, expires_at: 1.day.ago)
    ability = Ability.new(student)

    assert ability.cannot?(:edit, thesis)
    assert ability.cannot?(:update, thesis)
    assert ability.cannot?(:manage, document)
  end
end
