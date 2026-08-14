# frozen_string_literal: true

require 'test_helper'

class ReportsControllerTest < ActionController::TestCase
  setup do
    @user = create(:user, role: User::ADMIN)
    log_user_in(@user)
  end

  should 'calculate dashboard counts by status and embargo state' do
    create(:thesis, status: Thesis::OPEN)
    create(:thesis, status: Thesis::UNDER_REVIEW)
    create(:thesis, status: Thesis::REJECTED)
    create(:thesis, status: Thesis::REJECTED, embargoed: true)
    create(:thesis, status: Thesis::ACCEPTED)
    create(:thesis, status: Thesis::ACCEPTED, embargoed: true)
    create(:thesis, status: Thesis::PUBLISHED)
    create(:thesis, status: Thesis::PUBLISHED, embargoed: true)

    get :dashboard

    assert_equal 8, assigns(:theses_count)
    assert_equal 1, assigns(:theses_open_count)
    assert_equal 1, assigns(:theses_under_review_count)
    assert_equal 1, assigns(:theses_rejected_count)
    assert_equal 1, assigns(:theses_accepted_count)
    assert_equal 1, assigns(:theses_published_count)
    assert_equal 3, assigns(:theses_embargoed_count)
  end

  should 'show only theses without a published date for the default status report' do
    create(:thesis, status: Thesis::UNDER_REVIEW, published_date: nil)
    create(:thesis, status: Thesis::UNDER_REVIEW, published_date: Date.new(2024, 1, 2))

    get :by_status

    assert_equal Thesis::UNDER_REVIEW, assigns(:status)
    assert_equal 1, assigns(:null_date_count)
    assert_equal 1, assigns(:published_date_counts).values.sum
    assert_equal 1, assigns(:theses).size
    assert_nil assigns(:theses).first.published_date
  end

  should 'list all embargoed theses when the embargoed report is requested' do
    embargoed = create_list(:thesis, 2, status: Thesis::ACCEPTED, embargoed: true)
    create(:thesis, status: Thesis::ACCEPTED, embargoed: false)

    get :by_status, params: { status: 'embargoed' }

    assert_equal embargoed.map(&:id).sort, assigns(:theses).map(&:id).sort
  end

  should 'provide previous and next thesis ids when reviewing a status list' do
    first = create(:thesis, status: Thesis::UNDER_REVIEW, published_date: Date.new(2024, 1, 1))
    second = create(:thesis, status: Thesis::UNDER_REVIEW, published_date: Date.new(2024, 1, 2))
    third = create(:thesis, status: Thesis::UNDER_REVIEW, published_date: Date.new(2024, 1, 3))

    get :review_thesis, params: { id: second.id }

    assert_equal first.id, assigns(:prev_id)
    assert_equal third.id, assigns(:next_id)
  end
end
