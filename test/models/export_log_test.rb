require 'test_helper'

class ExportLogTest < ActiveSupport::TestCase
  should "create a valid export log" do
    log = build(:export_log)

    assert log.valid?

    assert_difference "ExportLog.count", 1 do
      log.save
    end

  end

  should "not create an invalid export log" do

    assert ! build(:export_log, creator: nil).valid?, "Should have a creator assigned"
    assert ! build(:export_log, job_status: nil).valid?, "Should have a job status set"
    assert ! build(:export_log, published_date: nil).valid?, "Should have a published_date set"

  end

  should "Return export logs based on status" do
    create_list(:export_log, 3, job_status: ExportLog::JOB_OPEN)
    create_list(:export_log, 2, job_status: ExportLog::JOB_RUNNING)
    create_list(:export_log, 4, job_status: ExportLog::JOB_DONE)
    create_list(:export_log, 5, job_status: ExportLog::JOB_FAILED)

    assert_equal 3, ExportLog.open.size
    assert_equal 2, ExportLog.running.size
    assert_equal 4, ExportLog.done.size
    assert_equal 5, ExportLog.failed.size
  end

end
