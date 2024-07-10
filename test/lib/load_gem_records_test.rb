require 'test_helper'

require Rails.root.join('lib/tasks/load_gem_records_csv.rb')
class LoadGemRecordsTest < ActiveSupport::TestCase
  setup do
    gem_load = LoadGemRecordsCSV.new
    gem_load.load_csv('lib/dummy_gem_records.csv')
  end

  should "parse csv" do
    puts "\nRunning test..."

    assert_equal 3, GemRecord.count

    records = GemRecord.order(:seqgradevent)

    assert_equal 1, records[0].seqgradevent
    assert_equal 'John Doe', records[0].studentname
    assert_equal 123456, records[0].sisid
    assert_equal 'johndoe@example.com', records[0].emailaddress

    assert_equal 2, records[1].seqgradevent
    assert_equal 'Jane Smith', records[1].studentname
    assert_equal 654321, records[1].sisid
    assert_equal 'janesmith@example.com', records[1].emailaddress

    assert_equal 3, records[2].seqgradevent
    assert_equal 'Alice Johnson', records[2].studentname
    assert_equal 789012, records[2].sisid
    assert_equal 'alicejohnson@example.com', records[2].emailaddress
  end
end
