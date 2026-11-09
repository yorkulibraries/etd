# frozen_string_literal: true

require 'application_system_test_case'
require Rails.root.join('lib/etd/exporter.rb')

# How the export page can fail FGS staff, written before the code:
# 1. Nothing in the menu links to it, so staff cannot find it.
# 2. The form still shows the misleading test/production, complete and publish options.
# 3. After a run the page does not say plainly how many theses were deposited or failed,
#    or whether licences were added (the old "Failed Count" box showed the success count).
# 4. A second export can be started while one is still waiting.
# 5. A failed thesis is not counted as failed, or is wrongly marked published.
# 6. Future publish dates are offered, so theses could go to YorkSpace early.
# 7. A thesis that may already be in YorkSpace is not named, so staff cannot get it checked.
# YorkSpace itself is replaced by a stand-in that accepts every deposit; nothing leaves this machine.
class DspaceExportsTest < ApplicationSystemTestCase
  class AcceptingYorkSpace
    def prepare_collection; end

    def deposit(**_arguments)
      Struct.new(:status_code, :status_message, :location, :entry).new(
        201, 'Created', 'https://ys.example/server/swordv2/edit/33333333-3333-4333-8333-333333333333', nil
      )
    end
  end

  class RejectingYorkSpace
    def prepare_collection; end

    def deposit(**_arguments)
      raise ETD::Exporter::NothingSent, 'YorkSpace did not accept the new item: server returned code 500'
    end
  end

  class HalfFinishingYorkSpace
    def prepare_collection; end

    def deposit(**_arguments)
      raise ETD::Exporter::PartialDeposit, 'YorkSpace made the item but a later step failed: server returned 500'
    end
  end

  # Runs after ApplicationSystemTestCase#setup has prepared the sign-in boundary.
  def setup
    super
    login_as(create(:user, role: User::ADMIN))
    # The most recent publish date (Mar 1, Jul 1 or Nov 1) that is today or earlier.
    @date = (Date.today - 1.year..Date.today).reverse_each.find { |day| [3, 7, 11].include?(day.month) && day.day == 1 }
    ETD::Exporter.stubs(:new).returns(AcceptingYorkSpace.new)
  end

  test 'staff run an export from the menu and read a plain summary' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: @date, title: 'Export Page Thesis')

    visit root_path
    click_link 'DSpace Export'
    click_link '+ DSpace Export'
    within 'div#new_export_log' do
      assert_no_text 'Export To Production Server?'
      assert_no_text 'Complete Submission?'
      assert_no_text 'Change status to published?'
      offered = all('#export_log_published_date option').map { |option| Date.parse(option.value) }
      assert offered.all? { |day| day <= Date.today }, "Future dates offered: #{offered}"
      find('#export_log_published_date').find("option[value='#{@date.iso8601}']").select_option
      click_button 'Queue Up Export'
    end

    assert_no_selector 'div#new_export_log', visible: true
    within('#export_logs_list') { assert_text @date.strftime('%b %d, %Y') }
    export_log = wait_for_finished_export
    visit export_log_path(export_log)

    assert_text 'Deposited 1 of 1 theses. Failed: 0.'
    assert_text 'Licences were not added: the DSpace REST API URL is blank on the Settings page.'
    assert_equal Thesis::PUBLISHED, thesis.reload.status
    assert_no_text 'Full Output'
    # Grow the window to the page height so the screenshot shows the whole results page.
    current_window.resize_to(1920, page.evaluate_script('document.documentElement.scrollHeight') + 40)
    page.save_screenshot('dspace-export-summary.png') # saved under Capybara.save_path, tmp/test-screenshots
  end

  test 'staff see a failed thesis counted and left to try again' do
    ETD::Exporter.stubs(:new).returns(RejectingYorkSpace.new)
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: @date)

    visit export_logs_path
    click_link '+ DSpace Export'
    within 'div#new_export_log' do
      find('#export_log_published_date').find("option[value='#{@date.iso8601}']").select_option
      click_button 'Queue Up Export'
    end
    visit export_log_path(wait_for_finished_export)

    within '#export_summary' do
      assert_text 'Deposited 0 of 1 theses. Failed: 1.'
      assert_text 'Theses that failed were left as accepted'
    end
    assert_no_text 'Full Output'
    assert_no_text 'What went wrong'
    assert_equal Thesis::ACCEPTED, thesis.reload.status
    current_window.resize_to(1920, page.evaluate_script('document.documentElement.scrollHeight') + 40)
    page.save_screenshot('dspace-export-failed.png')
  end

  test 'staff see which theses need checking in YorkSpace before they are sent again' do
    ETD::Exporter.stubs(:new).returns(HalfFinishingYorkSpace.new)
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: @date, title: 'Half Sent Thesis')

    visit export_logs_path
    click_link '+ DSpace Export'
    within 'div#new_export_log' do
      find('#export_log_published_date').find("option[value='#{@date.iso8601}']").select_option
      click_button 'Queue Up Export'
    end
    visit export_log_path(wait_for_finished_export)

    within '#export_summary' do
      assert_text 'Need checking in YorkSpace: 1.'
      assert_text 'Half Sent Thesis'
      assert_text 'will not be sent again until'
    end
    assert_equal Thesis::ACCEPTED, thesis.reload.status
    current_window.resize_to(1920, page.evaluate_script('document.documentElement.scrollHeight') + 40)
    page.save_screenshot('dspace-export-needs-checking.png')
  end

  test 'staff cannot start a second export while one is waiting' do
    create(:export_log, job_status: ExportLog::JOB_OPEN)

    visit export_logs_path
    click_link '+ DSpace Export'
    within 'div#new_export_log' do
      find('#export_log_published_date').find("option[value='#{@date.iso8601}']").select_option
      click_button 'Queue Up Export'
    end

    assert_text 'Another export is still waiting or running'
    assert_equal 1, ExportLog.count
    page.save_screenshot('dspace-export-blocked.png')
  end

  private

  def wait_for_finished_export
    Timeout.timeout(60) do
      loop do
        export_log = ExportLog.last
        return export_log if export_log && [ExportLog::JOB_DONE, ExportLog::JOB_FAILED].include?(export_log.job_status)

        sleep 0.2
      end
    end
  end
end
