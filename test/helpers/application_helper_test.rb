# frozen_string_literal: true

require 'test_helper'

class ApplicationHelperTest < ActiveSupport::TestCase
  class HelperContext
    include ApplicationHelper

    attr_accessor :current_user
  end

  setup do
    @student = create(:student)
    @helper = HelperContext.new
    @helper.current_user = @student
    @helper.instance_variable_set(:@current_user, @student)
  end

  test 'a draft request document remains editable after its thesis closes' do
    thesis = create(:thesis, student: @student, status: Thesis::ACCEPTED)
    request = create(:embargo_request, thesis: thesis, request_type: :extension)
    document = create(:embargo_request_document, embargo_request: request)

    assert_not @helper.block_document_changes?(document)
  end

  test 'a legacy document remains blocked after its thesis closes' do
    thesis = create(:thesis, student: @student, status: Thesis::ACCEPTED)
    document = create(:document, thesis: thesis, user: @student)

    assert @helper.block_document_changes?(document)
  end
end
