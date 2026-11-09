# frozen_string_literal: true

require 'test_helper'

class ExportLogsControllerTest < ActionController::TestCase
  include ActiveJob::TestHelper
  setup do
    @user = create(:user, role: User::ADMIN)
    log_user_in(@user)
    # Exports with nothing to send are refused, so most tests need one thesis that is ready.
    @ready = create(:thesis, status: Thesis::ACCEPTED, published_date: Date.new(2026, 11, 1))
  end

  should 'show export logs' do
    create_list(:export_log, 4, job_status: ExportLog::JOB_OPEN)
    create_list(:export_log, 3, job_status: ExportLog::JOB_RUNNING)
    create_list(:export_log, 5, job_status: ExportLog::JOB_DONE)
    create_list(:export_log, 2, job_status: ExportLog::JOB_CANCELLED)

    get :index
    assert_template :index

    export_logs = assigns(:export_logs)

    assert_not_nil export_logs, "Shouldn't be nil"

    assert_equal 4, export_logs.size, 'Should only be 4, open'

    get :index, params: { which: ExportLog::JOB_DONE }
    assert_template :index
    export_logs = assigns(:export_logs)
    assert_equal 5, export_logs.size, 'Should be 5 done'
  end

  should 'show new form for export log' do
    get :new
    assert_template :new
  end

  should 'create a new  export log' do
    assert_difference 'ExportLog.count', 1 do
      post :create, params: { export_log: { published_date: '2026-11-01' } }
      export_log = assigns(:export_log)
      assert export_log, 'Export Log was not assigned'
      assert_equal 0, export_log.errors.size, "There should be no errors, #{export_log.errors.messages}"
      assert_equal export_log.creator, @user, 'Creator should be manager user'
      assert_equal ExportLog::JOB_OPEN, export_log.job_status, 'Job Status should be new'

      assert_redirected_to export_logs_path, 'Should redirect back to export log'
    end
  end

  should 'capture only publication eligible thesis ids' do
    eligible = create(:thesis, status: Thesis::ACCEPTED, published_date: Date.new(2026, 7, 27))
    blocked = create(:thesis, status: Thesis::ACCEPTED, published_date: Date.new(2026, 7, 27))
    create(:submitted_embargo_request, thesis: blocked)

    post :create, params: {
      export_log: {
        published_date: '2026-07-27', complete_thesis: true,
        publish_thesis: true, production_export: false
      }
    }

    export_log = assigns(:export_log)
    assert_includes export_log.theses_ids.split(','), eligible.id.to_s
    assert_not_includes export_log.theses_ids.split(','), blocked.id.to_s
  end

  # How starting an export can go wrong, written before the code:
  # 1. Two exports run at once and deposit the same theses twice.
  # 2. An export that died (for example in a server restart) blocks every new export forever.
  # 3. Old form values (test server, no complete, no publish) still reach the job.
  should 'refuse a new export while another one is waiting or running' do
    [ExportLog::JOB_OPEN, ExportLog::JOB_RUNNING].each do |status|
      busy = create(:export_log, job_status: status)

      assert_no_difference 'ExportLog.count' do
        post :create, params: { export_log: { published_date: '2026-11-01' } }
      end
      assert_includes assigns(:export_log).errors.full_messages.join, 'Another export is still'

      busy.update_columns(job_status: ExportLog::JOB_DONE)
    end
  end

  should 'not let an export that stopped hours ago block a new one' do
    create(:export_log, job_status: ExportLog::JOB_RUNNING).update_columns(updated_at: 3.hours.ago)
    create(:export_log, job_status: ExportLog::JOB_FAILED)
    create(:export_log, job_status: ExportLog::JOB_CANCELLED)

    assert_difference 'ExportLog.count', 1 do
      post :create, params: { export_log: { published_date: '2026-11-01' } }
    end
  end

  # 4. An export that died stays in the Running tab forever, because only waiting exports can be cancelled.
  should 'let staff clear an export that stopped making progress, but not a live one' do
    stopped = create(:export_log, job_status: ExportLog::JOB_RUNNING)
    stopped.update_columns(updated_at: 3.hours.ago)
    live = create(:export_log, job_status: ExportLog::JOB_RUNNING)

    post :destroy, params: { id: stopped.id }
    post :destroy, params: { id: live.id }

    assert_equal ExportLog::JOB_CANCELLED, stopped.reload.job_status
    assert_equal ExportLog::JOB_RUNNING, live.reload.job_status
  end

  should 'always complete and publish, ignoring old test, complete and publish form values' do
    post :create, params: {
      export_log: { published_date: '2026-11-01', production_export: false,
                    complete_thesis: false, publish_thesis: false }
    }

    export_log = ExportLog.last
    assert export_log.complete_thesis?
    assert export_log.publish_thesis?
  end

  # Review round, written before the code:
  # 5. A future publish date is picked and theses go to YorkSpace months early.
  # 6. A thesis from an older date that is still waiting is left behind (the script sent it).
  # 7. An export with nothing in it is started.
  # 8. Two clicks at the same moment both pass the "one export at a time" check.
  # 9. Cancel is pressed just as the job starts, and the export is both cancelled and sending.
  should 'refuse a publish date after today' do
    future = EmbargoRequest.toronto_today + 1.day
    create(:thesis, status: Thesis::ACCEPTED, published_date: future)

    assert_no_difference 'ExportLog.count' do
      post :create, params: { export_log: { published_date: future.iso8601 } }
    end
    assert_includes assigns(:export_log).errors.full_messages.join, 'today or earlier'
  end

  should 'include accepted theses from earlier publish dates that are still waiting' do
    older = create(:thesis, status: Thesis::ACCEPTED, published_date: Date.new(2025, 3, 1))
    later = create(:thesis, status: Thesis::ACCEPTED, published_date: Date.new(2026, 11, 2))

    post :create, params: { export_log: { published_date: '2026-11-01' } }

    ids = ExportLog.last.theses_ids.split(',')
    assert_includes ids, older.id.to_s
    assert_includes ids, @ready.id.to_s
    assert_not_includes ids, later.id.to_s
  end

  should 'refuse an export with no theses ready to send' do
    @ready.update_columns(status: Thesis::PUBLISHED)

    assert_no_difference 'ExportLog.count' do
      post :create, params: { export_log: { published_date: '2026-11-01' } }
    end
    assert_includes assigns(:export_log).errors.full_messages.join, 'No accepted theses are ready'
  end

  should 'refuse the second of two exports that pass the check at the same moment' do
    create(:export_log, job_status: ExportLog::JOB_OPEN, active_slot: ExportLog::ACTIVE)
    ExportLog.any_instance.stubs(:no_other_active_export) # both requests checked before either saved

    assert_no_difference 'ExportLog.count' do
      assert_no_enqueued_jobs(only: DspaceExportJob) do
        post :create, params: { export_log: { published_date: '2026-11-01' } }
      end
    end
    assert_includes assigns(:export_log).errors.full_messages.join, 'Another export is still'
  end

  should 'not cancel an export the job started after the page was loaded' do
    export_log = create(:export_log, job_status: ExportLog::JOB_OPEN, active_slot: ExportLog::ACTIVE)
    ExportLog.where(id: export_log.id).update_all(job_status: ExportLog::JOB_RUNNING)

    assert_not export_log.cancel!(@user)
    assert_equal ExportLog::JOB_RUNNING, export_log.reload.job_status
  end

  should 'free the slot when an export is cancelled, so a new one can start' do
    waiting = create(:export_log, job_status: ExportLog::JOB_OPEN, active_slot: ExportLog::ACTIVE)

    post :destroy, params: { id: waiting.id }
    assert_difference 'ExportLog.count', 1 do
      post :create, params: { export_log: { published_date: '2026-11-01' } }
    end
    assert_nil waiting.reload.active_slot
  end

  # Item E (interim fix), written before the code:
  # 10. A server restart loses a queued export: it stays "waiting" forever and blocks every new export.
  # 11. The lost export starts late after a new one began, and both send.
  should 'not let a queued export that never started block a new one' do
    lost = create(:export_log, job_status: ExportLog::JOB_OPEN, active_slot: ExportLog::ACTIVE)
    lost.update_columns(created_at: 15.minutes.ago)

    assert_difference 'ExportLog.count', 1 do
      post :create, params: { export_log: { published_date: '2026-11-01' } }
    end

    lost.reload
    assert_equal ExportLog::JOB_FAILED, lost.job_status
    assert_nil lost.active_slot
    assert_includes lost.stop_reason, 'never started'
  end

  should 'still block a new export while a recent one waits to start' do
    create(:export_log, job_status: ExportLog::JOB_OPEN, active_slot: ExportLog::ACTIVE)
                .update_columns(created_at: 2.minutes.ago)

    assert_no_difference('ExportLog.count') { post :create, params: { export_log: { published_date: '2026-11-01' } } }
  end

  should 'not send a lost export if its job starts late' do
    lost = create(:export_log, job_status: ExportLog::JOB_OPEN, active_slot: ExportLog::ACTIVE,
                               theses_count: 1, theses_ids: @ready.id.to_s)
    lost.update_columns(created_at: 15.minutes.ago)
    post :create, params: { export_log: { published_date: '2026-11-01' } }
    exporter = mock('exporter')
    exporter.expects(:prepare_collection).never
    job = DspaceExportJob.new
    job.exporter = exporter

    job.perform(lost.id)

    assert_equal ExportLog::JOB_FAILED, lost.reload.job_status
  end

  should 'not update an an existing export log' do
    export_log = create(:export_log)

    assert_difference 'ExportLog.count', 0 do
      post :update, params: { id: export_log.id }
      assert_redirected_to export_logs_path, 'Should redirect back to export logs'
    end
  end

  should 'not remove an an existing export log, set it to canncelled' do
    export_log = create(:export_log, job_status: ExportLog::JOB_OPEN)

    assert_difference 'ExportLog.count', 0 do
      post :destroy, params: { id: export_log.id }
      l = assigns(:export_log)
      assert_equal l.job_status, ExportLog::JOB_CANCELLED
      assert_equal l.job_cancelled_by_id, @user.id, 'User id was recorded'
      assert_not_nil l.job_cancelled_at, 'Date was set'
      assert_redirected_to export_logs_path, 'Should redirect back to export logs'
    end
  end

  should 'not set export to cancelled if the job status is not JOB_OPEN' do
    export_log = create(:export_log, job_status: ExportLog::JOB_RUNNING)

    post :destroy, params: { id: export_log.id }
    l = assigns(:export_log)
    assert_equal l.job_status, ExportLog::JOB_RUNNING
  end
end
