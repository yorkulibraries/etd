# frozen_string_literal: true

require 'test_helper'

class ReportsControllerTest < ActionController::TestCase
  [User::STAFF, User::MANAGER, User::ADMIN].each do |role|
    test "#{role} can review a thesis" do
      log_user_in(create(:user, role: role))
      thesis = create(:thesis)

      get :review_thesis, params: { id: thesis.id }

      assert_response :success
      assert_equal thesis.id, assigns(:thesis).id
    end
  end

  test 'student cannot review a thesis before the report action queries it' do
    log_user_in(create(:student))
    Thesis.expects(:find).never

    get :review_thesis, params: { id: 123_456 }

    assert_redirected_to unauthorized_url
  end

  test 'nonstaff cannot review a thesis before the report action queries it' do
    log_user_in(create(:user, role: 'reviewer'))
    Thesis.expects(:find).never

    get :review_thesis, params: { id: 123_456 }

    assert_redirected_to unauthorized_url
  end

  test 'report document rendering excludes request-bound evidence metadata' do
    log_user_in(create(:user, role: User::STAFF))
    thesis = create(:thesis)
    request = create(:embargo_request, thesis: thesis)
    document = create(:document, thesis: thesis, user: thesis.student, embargo_request: request,
                               usage: :embargo_letter, name: 'private-letter.pdf',
                               file: Rack::Test::UploadedFile.new('test/fixtures/files/pdf-document.pdf'))

    get :review_thesis, params: { id: thesis.id }

    assert_response :success
    assert_not_includes response.body, document.name
    assert_not_includes response.body, document.file_url
  end
end
