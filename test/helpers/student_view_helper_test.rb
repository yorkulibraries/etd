# frozen_string_literal: true

require 'test_helper'

class StudentViewHelperTest < ActionView::TestCase
  should 'show the active accordion and badge for the current status' do
    @thesis = build(:thesis, status: Thesis::OPEN)

    assert_equal 'accordion-collapse collapse show', show_accordion(Thesis::OPEN)
    assert_equal 'badge text-bg-success', show_badge(Thesis::OPEN)
    assert_equal 'accordion-button ', collapse_accordion(Thesis::OPEN)
  end

  should 'collapse inactive statuses' do
    @thesis = build(:thesis, status: Thesis::OPEN)

    assert_equal 'accordion-collapse collapse ', show_accordion(Thesis::RETURNED)
    assert_equal 'badge text-bg-dark', show_badge(Thesis::RETURNED)
    assert_equal 'accordion-button collapsed', collapse_accordion(Thesis::RETURNED)
  end
end
