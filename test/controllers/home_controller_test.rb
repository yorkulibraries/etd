# frozen_string_literal: true

require 'test_helper'

class HomeControllerTest < ActionController::TestCase
  context 'as admin' do
    setup do
      @user = create(:user, role: User::ADMIN)
      log_user_in(@user)
    end

    should 'display index template' do
      get :index
      assert_response :success
      assert_template :index
    end

    should 'show open and returned theses by default and under reivew if present' do
      create_list(:thesis, 1, status: Thesis::OPEN)
      create_list(:thesis, 1, status: Thesis::RETURNED)
      create_list(:thesis, 2, status: Thesis::UNDER_REVIEW)

      get :index

      theses = assigns(:theses)
      which = assigns(:which)
      assert_equal 2, theses.size, 'Only 2 should be present, Open and returned'
      ## make sure only open and returned theses are there
      theses.each { |t| assert_not_equal Thesis::UNDER_REVIEW, t.status }

      assert_equal Thesis::OPEN, which, 'Open and returned'

      ## UNDER REVIEW
      get :index, params: { which: Thesis::UNDER_REVIEW }
      theses = assigns(:theses)
      which = assigns(:which)

      assert_equal 2, theses.size, 'Only 2 theses Under review'
      theses.each { |t| assert_equal Thesis::UNDER_REVIEW, t.status }
      assert_equal Thesis::UNDER_REVIEW, which, 'Under Review'
    end

    should 'show thesis assigned to current user when params which=mine' do
      create_list(:thesis, 1, status: Thesis::OPEN)
      create_list(:thesis, 1, status: Thesis::RETURNED)
      create_list(:thesis, 2, status: Thesis::UNDER_REVIEW).each { |t| t.assign_to(@user) }

      get :index, params: { which: 'mine'}
      theses = assigns(:theses)
      which = assigns(:which)

      assert_equal 2, theses.size
      theses.each { |t| assert_equal Thesis::UNDER_REVIEW, t.status }
      assert_equal 'mine', which
    end

    should 'show submitted embargo requests oldest first with a pending count' do
      newer = create(:submitted_embargo_request)
      older = create(:submitted_embargo_request)
      newer.update_columns(submitted_at: 1.day.ago)
      older.update_columns(submitted_at: 2.days.ago)
      create(:embargo_request, status: :declined, decided_at: Time.current, decided_by: @user)

      get :index, params: { which: 'embargo_requests', status: 'submitted' }

      assert_equal [older.id, newer.id], assigns(:embargo_requests).map(&:id)
      assert_equal 2, assigns(:pending_embargo_requests_count)
      assert_select '#embargo-requests-queue'
      assert_not_includes response.body, older.rationale
      assert_not_includes response.body, 'A private decision note'
      assert_not_includes response.body, 'private-letter.pdf'
    end

    should 'show terminal embargo requests newest first and fall back to submitted for an invalid filter' do
      older = create(:embargo_request, status: :approved, decided_at: 2.days.ago, decided_by: @user)
      newer = create(:embargo_request, status: :approved, decided_at: 1.day.ago, decided_by: @user)
      submitted = create(:submitted_embargo_request)

      get :index, params: { which: 'embargo_requests', status: 'approved' }
      assert_equal [newer.id, older.id], assigns(:embargo_requests).map(&:id)

      get :index, params: { which: 'embargo_requests', status: 'not-a-status' }
      assert_equal 'submitted', assigns(:embargo_status)
      assert_equal [submitted.id], assigns(:embargo_requests).map(&:id)
    end
  end

  [User::STAFF, User::MANAGER, User::ADMIN].each do |role|
    test "#{role} can view the embargo request queue" do
      log_user_in(create(:user, role: role))
      create(:submitted_embargo_request)

      get :index, params: { which: 'embargo_requests' }

      assert_response :success
      assert_equal 'embargo_requests', assigns(:which)
    end
  end

  context 'as student' do
    setup do
      @student = create(:student)
      log_user_in(@student)
    end

    should 'redirect student user to student view' do
      get :index
      assert_response :redirect
      assert_redirected_to student_view_index_url
    end
  end
end
