require 'test_helper'

require Rails.root.join('lib/tasks/load_gem_records_csv.rb')
class LoadGemRecordsTest < ActiveSupport::TestCase

  GEM_RECORDS_FILE = "test/fixtures/files/gem_records.csv"
  COMMITTEE_MEMBERS_FILE = "test/fixtures/files/committee_members.csv"

  should "parse csv" do
    gem_load = LoadGemRecordsCSV.new
    gem_load.load_gem_records(LoadGemRecordsTest::GEM_RECORDS_FILE)
    gem_load.load_committee_members(LoadGemRecordsTest::COMMITTEE_MEMBERS_FILE)

    assert_equal 3, GemRecord.count

    records = GemRecord.order(:seqgradevent)

    assert_equal 1, records[0].seqgradevent
    assert_equal 'Doe, John Middle Name', records[0].studentname
    assert_equal 123456789, records[0].sisid
    assert_equal 'johndoe@example.com', records[0].emailaddress
    assert_equal 'Supervisor, X', records[0].superv

    assert_equal 2, records[1].seqgradevent
    assert_equal 'Smith, Jane Mid N', records[1].studentname
    assert_equal 654321476, records[1].sisid
    assert_equal 'janesmith@example.com', records[1].emailaddress
    assert_equal 'Supervisor, Y', records[1].superv

    assert_equal 3, records[2].seqgradevent
    assert_equal 'Johnson, Alice Middle N', records[2].studentname
    assert_equal 789012185, records[2].sisid
    assert_equal 'alicejohnson@example.com', records[2].emailaddress
    assert_equal 'Supervisor, Z', records[2].superv

    assert_equal 2, records[0].committee_members.count
    assert_equal 'John', records[0].committee_members.first.first_name
    assert_equal 'Smith', records[0].committee_members.first.last_name
    assert_equal 'Chair', records[0].committee_members.first.role

    assert_equal 'Jane', records[0].committee_members.last.first_name
    assert_equal 'Doe', records[0].committee_members.last.last_name
    assert_equal 'Committee Member', records[0].committee_members.last.role

    assert_equal 2, records[1].committee_members.count
    assert_equal 'Jim', records[1].committee_members.first.first_name
    assert_equal 'Brown', records[1].committee_members.first.last_name
    assert_equal 'Chair', records[1].committee_members.first.role

    assert_equal 'Jake', records[1].committee_members.last.first_name
    assert_equal 'White', records[1].committee_members.last.last_name
    assert_equal 'Committee Member', records[1].committee_members.last.role

    assert_equal 2, records[2].committee_members.count
    assert_equal 'Eve', records[2].committee_members.first.first_name
    assert_equal 'Green', records[2].committee_members.first.last_name
    assert_equal 'Chair', records[2].committee_members.first.role

    assert_equal 'Frank', records[2].committee_members.last.first_name
    assert_equal 'Black', records[2].committee_members.last.last_name
    assert_equal 'Committee Member', records[2].committee_members.last.role
  end

  should "not delete existing GEM records when loading GEM records from CSV" do
    # create 5 GEM records w/ 3 committee members in each record
    create_list(:gem_record, 5)
    assert_equal 5, GemRecord.count

    # there should be 15 CommitteeMember
    assert_equal 15, CommitteeMember.count

    # load 3 GEM records from CSV files
    gem_load = LoadGemRecordsCSV.new
    gem_load.load_gem_records(LoadGemRecordsTest::GEM_RECORDS_FILE)
    gem_load.load_committee_members(LoadGemRecordsTest::COMMITTEE_MEMBERS_FILE)

    # there should be 8 GEM records at this point
    assert_equal 8, GemRecord.count

    # there should be 21 CommitteeMember
    assert_equal 21, CommitteeMember.count

    # load 3 GEM records from the exact same CSV files AGAIN
    gem_load = LoadGemRecordsCSV.new
    gem_load.load_gem_records(LoadGemRecordsTest::GEM_RECORDS_FILE)
    gem_load.load_committee_members(LoadGemRecordsTest::COMMITTEE_MEMBERS_FILE)

    # there should STILL be 8 GEM records at this point
    assert_equal 8, GemRecord.count

    # there should STILL be 21 CommitteeMember
    assert_equal 21, CommitteeMember.count
  end

  should "update existing and matching GEM records when loading GEM records from CSV" do
    # load 3 GEM records from CSV files
    gem_load = LoadGemRecordsCSV.new
    gem_load.load_gem_records(LoadGemRecordsTest::GEM_RECORDS_FILE)
    gem_load.load_committee_members(LoadGemRecordsTest::COMMITTEE_MEMBERS_FILE)

    # there should be 3 GEM records at this point
    assert_equal 3, GemRecord.count

    # load 3 GEM records from the exact same CSV files AGAIN
    gem_load = LoadGemRecordsCSV.new
    gem_load.load_gem_records(LoadGemRecordsTest::GEM_RECORDS_FILE)
    gem_load.load_committee_members(LoadGemRecordsTest::COMMITTEE_MEMBERS_FILE)

    # there should STILL be 3 GEM records at this point
    assert_equal 3, GemRecord.count


    records = GemRecord.order(:seqgradevent)

    # verify fields are correct
    assert_equal 1, records[0].seqgradevent
    assert_equal 'Doe, John Middle Name', records[0].studentname
    assert_equal 123456789, records[0].sisid
    assert_equal 'johndoe@example.com', records[0].emailaddress
    assert_equal 'Supervisor, X', records[0].superv

    # change the fields
    records[0].studentname = 'does not matter'
    records[0].sisid = 'does not matter'
    records[0].emailaddress = 'does not matter'
    records[0].save!

    # RELOAD 3 GEM records from the exact same CSV files AGAIN
    gem_load = LoadGemRecordsCSV.new
    gem_load.load_gem_records(LoadGemRecordsTest::GEM_RECORDS_FILE)
    gem_load.load_committee_members(LoadGemRecordsTest::COMMITTEE_MEMBERS_FILE)

    records = GemRecord.order(:seqgradevent)

    # there should STILL be 3 GEM records at this point
    assert_equal 3, GemRecord.count

    # there should STILL be 6 CommitteeMember
    assert_equal 6, CommitteeMember.count

    # verify fields are updated from the CSV
    assert_equal 1, records[0].seqgradevent
    assert_equal 'Doe, John Middle Name', records[0].studentname
    assert_equal 123456789, records[0].sisid
    assert_equal 'johndoe@example.com', records[0].emailaddress
    assert_equal 'Supervisor, X', records[0].superv

  end
end
