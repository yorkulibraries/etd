# frozen_string_literal: true

require 'test_helper'

class StudentsHelperTest < ActionView::TestCase
  should 'format audit values for empty, boolean, list, and structured values' do
    assert_equal '(blank)', audit_change_value(nil)
    assert_equal '(blank)', audit_change_value('')
    assert_equal '(blank)', audit_change_value([])
    assert_equal '(blank)', audit_change_value({})
    assert_equal 'Yes', audit_change_value(true)
    assert_equal 'No', audit_change_value(false)
    assert_equal 'one, two', audit_change_value(%w[one two])
    assert_equal 'Enabled: Yes, Tags: one, two',
                 audit_change_value(enabled: true, tags: %w[one two])
  end
end
