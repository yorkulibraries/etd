# frozen_string_literal: true

require 'test_helper'

class GemRecordsControllerTest < ActionController::TestCase
  setup do
    @user = create(:user, role: User::ADMIN)
    log_user_in(@user)
  end

  should 'list all records, if all parameter is passed along' do
    create_list(:gem_record, 2, eventtype: 'WHATEVER')
    create_list(:gem_record, 10, eventtype: GemRecord::PHD_EXAM)

    get :index, params: { all: true }

    records = assigns(:gem_records)
    assert_equal 12, records.size, 'Displaying all records, not just completed ones'
  end

  should 'List only 20 GemRecords at a time, and shows the paginate section in the template' do
    create_list(:gem_record, 25, eventtype: GemRecord::MASTERS_EXAM, examresult: GemRecord::ACCEPTED)
    create_list(:gem_record, 25, eventtype: GemRecord::PHD_EXAM, examresult: GemRecord::ACCEPTED)

    get :index
    records = assigns(:gem_records)
    assert records, 'Records should not be nil'
    assert_equal 20, records.size, 'Should display 20 at a time'

    get :index, params: { page: 3 }
    records = assigns(:gem_records)
    assert records, 'Should not be nil'
    assert_equal 10, records.size

    assert_template 'index', 'Index template should be displayed'
  end

  should 'committee members included in gem records'
    gem_records = create_list(:gem_record, 5, eventtype: GemRecord::PHD_EXAM)
    gem_records.each do |record|
      create_list(:committee_member, 2, gem_record: record)
    end
    
    get :index, params: { all: true }

    records = assigns(:gem_records)

    records.each do |record|
      assert record.committee_members.count >= 1, 'Each gem record should have at least one committee member'
    end
  end
end
