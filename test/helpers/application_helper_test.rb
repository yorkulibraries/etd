# frozen_string_literal: true

require 'test_helper'

class ApplicationHelperTest < ActionView::TestCase
  should 'expose the application version' do
    assert_equal '1.3.1', app_version
  end

  should 'block thesis changes for students after submission' do
    @current_user = build(:student)

    assert block_thesis_changes?(build(:thesis, status: Thesis::UNDER_REVIEW))
    assert_not block_thesis_changes?(build(:thesis, status: Thesis::OPEN))
    assert_not block_thesis_changes?(nil)
  end

  should 'allow staff to change theses in any status' do
    @current_user = build(:user, role: User::STAFF)

    assert_not block_thesis_changes?(build(:thesis, status: Thesis::UNDER_REVIEW))
  end

  should 'return an empty link for an unsupported auditable object' do
    assert_equal '', auditable_link(Object.new)
  end
end
