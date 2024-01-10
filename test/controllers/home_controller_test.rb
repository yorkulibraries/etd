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
  end

  context 'as student' do
    setup do
      @student = create(:student)
      log_user_in(@student)
    end

    should 'redirect to student view' do
      get :index
      assert_response :redirect
      assert_redirected_to student_view_index_url
    end
  end
end
