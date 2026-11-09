# frozen_string_literal: true

require 'test_helper'

class ExportLogTest < ActiveSupport::TestCase
  should 'create a valid export log' do
    log = build(:export_log)

    assert log.valid?

    assert_difference 'ExportLog.count', 1 do
      log.save
    end
  end

  should 'not create an invalid export log' do
    assert !build(:export_log, creator: nil).valid?, 'Should have a creator assigned'
    assert !build(:export_log, job_status: nil).valid?, 'Should have a job status set'
    assert !build(:export_log, published_date: nil).valid?, 'Should have a published_date set'
  end

  should 'Return export logs based on status' do
    create_list(:export_log, 3, job_status: ExportLog::JOB_OPEN)
    create_list(:export_log, 2, job_status: ExportLog::JOB_RUNNING)
    create_list(:export_log, 4, job_status: ExportLog::JOB_DONE)
    create_list(:export_log, 5, job_status: ExportLog::JOB_FAILED)

    assert_equal 3, ExportLog.open.size
    assert_equal 2, ExportLog.running.size
    assert_equal 4, ExportLog.done.size
    assert_equal 5, ExportLog.failed.size
  end

  # Written before the code: two waiting or running exports must be impossible even when both
  # requests pass the friendly check together; a thesis can only have one unresolved send.
  should 'let the database hold only one active export' do
    create(:export_log, active_slot: ExportLog::ACTIVE)

    assert_raises(ActiveRecord::RecordNotUnique) { create(:export_log, active_slot: ExportLog::ACTIVE) }
    assert_difference('ExportLog.count', 2) { create_list(:export_log, 2, active_slot: nil) }
  end

  should 'let the database hold only one unresolved send per thesis' do
    thesis = create(:thesis)
    assert ThesisDepositAttempt.claim(thesis:, export_log: create(:export_log))
    assert_nil ThesisDepositAttempt.claim(thesis:, export_log: create(:export_log))
  end

  should 'keep a send held back when saving its result fails' do
    thesis = create(:thesis)
    attempt = ThesisDepositAttempt.claim(thesis:, export_log: create(:export_log))
    attempt.stubs(:save!).raises(ActiveRecord::StatementInvalid, 'Incorrect string value')

    assert_raises(ActiveRecord::StatementInvalid) { attempt.failed!('nothing sent') }

    assert_equal thesis.id, attempt.open_thesis_id
    assert_equal ThesisDepositAttempt::SENDING, attempt.state
    assert_equal thesis.id, ThesisDepositAttempt.find(attempt.id).open_thesis_id
  end
end
