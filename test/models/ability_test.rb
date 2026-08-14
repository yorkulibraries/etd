# frozen_string_literal: true

require 'test_helper'

class AbilityTest < ActiveSupport::TestCase
  should 'give administrators and managers unrestricted management access' do
    [User::ADMIN, User::MANAGER].each do |role|
      ability = Ability.new(build(:user, role: role))

      assert ability.can?(:manage, :all), "#{role} should manage all resources"
      assert ability.can?(:embargo, :student), "#{role} should be able to embargo students"
    end
  end

  should 'limit staff to their explicitly assigned actions' do
    staff = build(:user, role: User::STAFF)
    ability = Ability.new(staff)

    assert ability.can?(:read, GemRecord)
    assert ability.can?(:manage, Document)
    assert ability.can?(:update_status, Thesis)
    assert ability.cannot?(:destroy, Thesis)
    assert ability.cannot?(:manage, :all)
    assert ability.cannot?(:embargo, :student)
  end

  should 'let a student manage documents only for their open or returned thesis' do
    student = create(:student)
    other_student = create(:student)
    open_thesis = build(:thesis, student: student, status: Thesis::OPEN)
    returned_thesis = build(:thesis, student: student, status: Thesis::RETURNED)
    under_review_thesis = build(:thesis, student: student, status: Thesis::UNDER_REVIEW)
    other_thesis = build(:thesis, student: other_student, status: Thesis::OPEN)
    ability = Ability.new(student)

    assert ability.can?(:manage, build(:document, thesis: open_thesis))
    assert ability.can?(:manage, build(:document, thesis: returned_thesis))
    assert ability.cannot?(:manage, build(:document, thesis: under_review_thesis))
    assert ability.cannot?(:manage, build(:document, thesis: other_thesis))
  end

  should 'let a student edit and submit only their open or returned thesis' do
    student = create(:student)
    other_student = create(:student)
    open_thesis = build(:thesis, student: student, status: Thesis::OPEN)
    returned_thesis = build(:thesis, student: student, status: Thesis::RETURNED)
    under_review_thesis = build(:thesis, student: student, status: Thesis::UNDER_REVIEW)
    other_thesis = build(:thesis, student: other_student, status: Thesis::OPEN)
    ability = Ability.new(student)

    assert ability.can?(:edit, open_thesis)
    assert ability.can?(:submit_for_review, returned_thesis)
    assert ability.cannot?(:edit, under_review_thesis)
    assert ability.cannot?(:show, other_thesis)
    assert ability.cannot?(:destroy, open_thesis)
  end
end
