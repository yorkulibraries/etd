# frozen_string_literal: true

require 'test_helper'

class ThesisSubjectshipTest < ActiveSupport::TestCase
  should belong_to(:thesis)
  should belong_to(:loc_subject)

  should 'persist a subject association and its rank' do
    thesis = create(:thesis)
    subject = create(:loc_subject)

    subjectship = ThesisSubjectship.create!(thesis: thesis, loc_subject: subject, rank: 2)

    assert_equal thesis, subjectship.thesis
    assert_equal subject, subjectship.loc_subject
    assert_equal 2, subjectship.rank
  end
end
