# frozen_string_literal: true

require 'test_helper'

class CommitteeMembersHelperTest < ActionView::TestCase
  context 'sort_by_last_name' do
    should 'return empty array if passed an empty or nil list' do
      assert_not_nil sort_by_last_name(nil)
      assert_equal 0, sort_by_last_name(nil).size
    end

    should 'list members sorted by last name' do
      list = ['John Xavier', 'Mandy Moore', 'Abe Abraham']

      result = sort_by_last_name(list)

      # expecting ["Abraham, Abe", "Moore, Mandy", "Xavier, John"]

      assert_equal 3, result.size, 'Should have three items'
      assert_equal 'Abraham, Abe', result.first.first, 'First should be abe'
      assert_equal 'Xavier, John', result.last.first, 'Last should be john'
    end

    should 'trim the member name and remove trailing spaces before sortin' do
      list = ['john doe '] # space at the end required for testing

      result = sort_by_last_name(list)
      assert_equal 'doe, john', result.first.first
    end
  end
end
