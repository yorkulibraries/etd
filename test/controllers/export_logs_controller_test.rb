require 'test_helper'

class ExportLogsControllerTest < ActionController::TestCase

  setup do
    @user = create(:user, role: User::ADMIN)
    log_user_in(@user)
  end


  should "show export logs" do
    create_list(:export_log,4, job_status: ExportLog::JOB_OPEN)
    create_list(:export_log, 3, job_status: ExportLog::JOB_RUNNING)
    create_list(:export_log, 5, job_status: ExportLog::JOB_DONE)
    create_list(:export_log, 2, job_status: ExportLog::JOB_CANCELLED)

    get :index
    assert_template :index

    export_logs = assigns(:export_logs)


    assert_not_nil export_logs, "Shouldn't be nil"


    assert_equal 4, export_logs.size, "Should only be 4, open"

    get :index, params: { which: ExportLog::JOB_DONE }
    assert_template :index
    export_logs = assigns(:export_logs)
    assert_equal 5, export_logs.size, "Should be 5 done"
  end


  should "show new form for export log" do
    get :new
    assert_template :new
  end

  should "create a new  export log" do
    assert_difference "ExportLog.count", 1 do
      post :create, params: { export_log: { published_date: "2017-01-01" } }
      export_log = assigns(:export_log)
      assert export_log, "Export Log was not assigned"
      assert_equal 0, export_log.errors.size, "There should be no errors, #{export_log.errors.messages}"
      assert_equal export_log.creator, @user, "Creator should be manager user"
      assert_equal ExportLog::JOB_OPEN, export_log.job_status, "Job Status should be new"

      assert_redirected_to export_logs_path, "Should redirect back to export log"
    end
  end

  should "not update an an existing export log" do
    export_log = create(:export_log)

    assert_difference "ExportLog.count", 0 do
      post :update, params: { id: export_log.id }
      assert_redirected_to export_logs_path, "Should redirect back to export logs"
    end
  end

  should "not remove an an existing export log, set it to canncelled" do
    export_log = create(:export_log, job_status: ExportLog::JOB_OPEN)

    assert_difference "ExportLog.count", 0 do
      post :destroy, params: { id: export_log.id }
      l = assigns(:export_log)
      assert_equal l.job_status, ExportLog::JOB_CANCELLED
      assert_equal l.job_cancelled_by_id, @user.id, "User id was recorded"
      assert_not_nil l.job_cancelled_at, "Date was set"
      assert_redirected_to export_logs_path, "Should redirect back to export logs"
    end
  end

  should "not set export to cancelled if the job status is not JOB_OPEN" do
    export_log = create(:export_log, job_status: ExportLog::JOB_RUNNING)

    post :destroy, params: { id: export_log.id }
    l = assigns(:export_log)
    assert_equal l.job_status, ExportLog::JOB_RUNNING

  end

end
