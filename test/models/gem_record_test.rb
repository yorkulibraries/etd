require 'test_helper'

class GemRecordTest < ActiveSupport::TestCase
  should 'paginate gem Record lists, 20 per page by default' do
    create_list(:gem_record, 40)

    records = GemRecord.page(1)
    assert_equal 20, records.size
  end

  should 'not be able to create a new GemRecord or update an existing one' do
    record = build(:gem_record)

    assert_no_difference 'GemRecord.count', 'Should not create a new record' do
      record.save
    end

    record = create(:gem_record, sisid: '222222222')

    record.sisid = '111111111'
    record.save

    record.reload
    assert_equal '222222222', record.sisid.to_s
  end

  should 'not be able to destroy GemRecord' do
    record = create(:gem_record)

    assert_no_difference 'GemRecord.count', 'Should not destroy existing records' do
      record.destroy
    end
  end

  should "show completed records with #{GemRecord::PHD_COMPLETED} or #{GemRecord::MASTERS_COMPLETED}" do
    create_list(:gem_record, 10, eventtype: 'SOMETHING ELSE')
    create_list(:gem_record, 5, eventtype: GemRecord::PHD_COMPLETED)
    create_list(:gem_record, 5, eventtype: GemRecord::MASTERS_COMPLETED)

    assert_equal 10, GemRecord.completed.count, 'Should include only 10 records of PHD or MASTERS Completion'
  end

  should "show exam records with #{GemRecord::PHD_EXAM} or #{GemRecord::MASTERS_EXAM}" do
    create_list(:gem_record, 10, eventtype: 'SOMETHING ELSE')
    create_list(:gem_record, 5, eventtype: GemRecord::PHD_EXAM)
    create_list(:gem_record, 5, eventtype: GemRecord::MASTERS_EXAM)

    assert_equal 10, GemRecord.exam.count, 'Should include only 10 records of PHD or MASTERS Exam'
  end

  should 'delete all GemRecords' do
    create_list(:gem_record, 3)

    before = GemRecord.count
    GemRecord.delete_all
    after = GemRecord.count
    assert_not_equal 0, before, 'Should have some records in there'
    assert_equal 0, after, 'Should have no records after delete all'
  end

  #### FINDERS ####
  should 'find gem record based on sisid or student name' do
    create(:gem_record, sisid: '222222222', studentname: 'John Doe')
    create(:gem_record, sisid: '111111111', studentname: 'John Smith')

    assert_equal 1, GemRecord.find_by_sisid_or_name('222222222').size, 'one with sisid 222'
    assert_equal 1, GemRecord.find_by_sisid_or_name('doe').size, 'One doe'
    assert_equal 2, GemRecord.find_by_sisid_or_name('john').size, 'Should be two Johns'
    assert_equal 0, GemRecord.find_by_sisid_or_name('brandon').size, 'No one was found'
  end

  # should "load new gem records via stdin" do
  #
  #     require Rails.root.join('lib/tasks/load_gem_records.rb')
  #     GemRecord.delete_all
  #     # file = File.open("lib/tasks/gem_records.txt")
  #
  #     loader = LoadGemRecords.new
  #     # system("cat " + Rails.root.join("lib/tasks/gem_records.txt").to_s + " | /usr/bin/rake gem_records:load RAILS_ENV=test")
  #     # system("cat lib/tasks/gem_records.txt | head -3")
  #     loader.load_stdin() << system("cat lib/tasks/gem_records.txt | head -3")
  #
  #
  #     assert_not_equal 0, GemRecord.count, "New records should have been loaded. Something went wrong load_gem_records or file"
  #
  #   end
end
