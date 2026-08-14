# frozen_string_literal: true

require 'test_helper'

class ThesesHelperTest < ActionView::TestCase
  def current_user
    @current_user
  end

  should 'render blank fields with the empty-field marker' do
    assert_equal '<span class="empty-field">Not filled in...</span>', format(nil)
    assert_equal '<span class="empty-field">Missing</span>', format('', false, 'Missing')
  end

  should 'format dates and rich text values' do
    assert_equal 'January 02, 2024', format(Date.new(2024, 1, 2))
    assert_equal "<p>Hello\n<br />world</p>", format("Hello\nworld", true)
  end

  should 'make immutable fields read-only only for students' do
    @current_user = build(:student)
    assert read_only_if_student('title')
    assert_not read_only_if_student('notes')

    @current_user = build(:user, role: User::STAFF)
    assert_not read_only_if_student('title')
  end

  should 'allow only administrators and managers to assign theses' do
    @current_user = build(:user, role: User::ADMIN)
    assert can_assign_to_anyone?

    @current_user = build(:user, role: User::MANAGER)
    assert can_assign_to_anyone?

    @current_user = build(:user, role: User::STAFF)
    assert_not can_assign_to_anyone?
  end

  should 'return publication dates on the supported quarterly boundaries' do
    dates = publish_on_dates(0.days)

    assert dates.all? { |label, value| label.match?(/\A(?:Mar|Jul|Nov)  1, \d{4}\z/) }
    assert dates.all? { |_label, value| value.match?(/\A\d{4}-(?:03|07|11)-01\z/) }
  end
end
