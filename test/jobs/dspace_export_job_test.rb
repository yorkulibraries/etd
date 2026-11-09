# frozen_string_literal: true

require 'test_helper'
require 'rake'

extend Rake::DSL

load Rails.root.join('lib/tasks/dspace_exporter.rake').to_s unless Rake::Task.task_defined?('dspace:export')
Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)

# How the website export job can go wrong for FGS, written before the code for these cases:
# A. Licences are only added when an old "production" box was ticked, so normal exports get none.
# B. An old or hand-made export log with "complete" or "publish" off leaves YorkSpace items unfinished,
#    or leaves deposited theses as accepted so the next export of that date sends them again.
# C. An export cancelled before it started still deposits.
# D. YorkSpace is unreachable or the login is wrong: the export stays "running" forever with no error.
# E. One thesis fails and the run stops, or the page gives no plain count of what happened.
# F. Start and finish times are never recorded.
# Added in the review round (see the worklog for the full list):
# G. A send fails after YorkSpace made the item, or the result is unknown (timeout, server stopped):
#    the thesis was counted failed and resent as a second item. -> "needs checking", held back.
# H. YorkSpace refuses the item: nothing was kept, so the thesis must stay free to try again.
# I. The YorkSpace library's own error stopped the whole export instead of only that thesis.
# J. Marking the thesis published fails after the deposit: it was counted as done.
# K. The export was cancelled or cleared while running, but the old job kept sending.
# L. The licence handoff failed and the page said "No licences were needed".
# M. The page said "Deposited 0 of 0" when YorkSpace could not be reached at all.
# O. A result cannot be saved (for example an emoji, which the utf8mb3 tables cannot store): the
#    attempt's hold was cleared in memory and then saved by the fallback, so a thesis that may be in
#    YorkSpace could be sent again. -> messages are made storable; a failed save keeps the hold.
# N. The log column fills up on a big export (about 64KB on MySQL) and the write error stops the export,
#    possibly right after a thesis was accepted by YorkSpace. -> the log is capped and can never stop it.
class DspaceExportJobTest < ActiveJob::TestCase
  RECEIPT = Struct.new(:status_code, :status_message, :location, :entry)

  # Fails one deposit (by number) with the given error; every other deposit is accepted.
  class FailingExporter
    attr_reader :calls

    def initialize(error, on_call: 1)
      @error = error
      @on_call = on_call
      @calls = 0
    end

    def prepare_collection; end

    def deposit(**_arguments)
      @calls += 1
      raise @error if @calls == @on_call

      RECEIPT.new(201, 'Created', "https://ys.example/swordv2/edit/item-#{@calls}", nil)
    end
  end
  class FailingSecondExporter
    def initialize
      @calls = 0
    end

    def prepare_collection; end

    def deposit(**_arguments)
      @calls += 1
      raise ETD::Exporter::NothingSent, 'YorkSpace refused the new item: server returned code 500' if @calls == 2

      OpenStruct.new(status_code: 201, status_message: 'Created')
    end
  end

  class UnreachableExporter
    def prepare_collection
      raise "Can't Connect To the Service. 401 Unauthorized"
    end
  end

  class RequestingExporter
    attr_reader :deposited_count

    def initialize(&block_second_thesis)
      @block_second_thesis = block_second_thesis
      @deposited_count = 0
    end

    def prepare_collection; end

    def deposit(entry:, files:, zipped:, complete:)
      @deposited_count += 1
      @block_second_thesis.call if @deposited_count == 1
      OpenStruct.new(status_code: 201, status_message: 'Created')
    end
  end

  class RecordingExporter
    attr_reader :deposits

    def initialize
      @deposits = []
    end

    def prepare_collection; end

    def deposit(entry:, files:, zipped:, complete:)
      @deposits << { entry: entry, files: files, zipped: zipped, complete: complete }
      OpenStruct.new(status_code: 201, status_message: 'Created')
    end
  end

  class SuccessfulExporter
    def prepare_collection; end

    def deposit(**_arguments)
      Struct.new(:status_code, :status_message, :location, :entry).new(
        201,
        'Created',
        'https://repository.example/server/swordv2/edit/22222222-2222-4222-8222-222222222222',
        nil
      )
    end
  end

  should 'export only primary and thesis supplemental file paths' do
    thesis = create(:thesis)
    primary = create(:document, thesis:, supplemental: false, usage: :thesis,
                                file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))
    supplemental = create(:document, thesis:, supplemental: true, usage: :thesis,
                                    file: fixture_file_upload('pdf-document.pdf'))
    licence = create(:document_licence, thesis:)
    embargo = create(:document, thesis:, supplemental: true, usage: :embargo,
                              file: fixture_file_upload('pdf-document.pdf'))
    request = create(:embargo_request, thesis: thesis)
    # Document#embargo_request_evidence_usage now rejects this combination, so a
    # record like this can only reach the database as legacy or corrupted data.
    # The export must still exclude it, which is what this regression guards.
    request_bound = build(:document, thesis: thesis, usage: :thesis, supplemental: true,
                                   embargo_request: request,
                                   file: fixture_file_upload('document-microsoft.doc'))
    request_bound.save!(validate: false)
    modification_request = create(:document, thesis:, supplemental: true, usage: :modification_request,
                                           file: fixture_file_upload('document-microsoft.doc'))

    paths = DspaceExportJob.new.extract_thesis_filepaths(thesis)

    assert_includes paths, primary.file.path
    assert_includes paths, supplemental.file.path
    assert_not_includes paths, licence.file.path
    assert_not_includes paths, embargo.file.path
    assert_not_includes paths, request_bound.file.path
    assert_not_includes paths, modification_request.file.path
  end

  should 'recheck embargo eligibility after an export log captured ids' do
    eligible = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    newly_blocked = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    export_log = create(:export_log, theses_ids: [eligible.id, newly_blocked.id].join(','), theses_count: 2)
    create(:submitted_embargo_request, thesis: newly_blocked)

    job = DspaceExportJob.new
    job.export_log = export_log

    assert_equal [eligible.id], job.send(:eligible_theses).pluck(:id)
  end

  should 'rechecks eligibility immediately before each DSpace deposit' do
    first = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago, title: 'First thesis')
    second = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago, title: 'Second thesis')
    export_log = create(:export_log, theses_ids: [first.id, second.id].join(','), theses_count: 2)
    exporter = RequestingExporter.new { create(:submitted_embargo_request, thesis: second) }
    job = DspaceExportJob.new
    job.exporter = exporter
    job.sleep_interval = 0

    job.perform(export_log.id)

    assert_equal 1, exporter.deposited_count
  end

  should 'never deposits request bound thesis usage documents' do
    thesis = create(:thesis)
    primary = create(:document, thesis: thesis, usage: :thesis, supplemental: false,
                                file: Rack::Test::UploadedFile.new('test/fixtures/files/pdf-document.pdf'))
    request = create(:embargo_request, thesis: thesis)
    request_bound = build(:document, thesis: thesis, embargo_request: request, usage: :thesis, supplemental: true)
    request_bound.save!(validate: false) # Simulate a malformed historical row predating the validation.

    files = DspaceExportJob.new.extract_thesis_filepaths(thesis)

    assert_includes files, primary.file.path
    assert_not_includes files, request_bound.file.path
  end

  should 'keeps permanent, pending, and active approval embargoes out of every rake selector' do
    permanent = create(:thesis, status: Thesis::ACCEPTED, embargoed: true, published_date: 1.day.ago)
    pending = create(:thesis, status: Thesis::ACCEPTED, published_date: 1.day.ago)
    approved = create(:thesis, status: Thesis::PUBLISHED, published_date: 1.day.ago)
    eligible = create(:thesis, status: Thesis::ACCEPTED, published_date: 1.day.ago)
    create(:submitted_embargo_request, thesis: pending)
    create(:embargo_request, thesis: approved, status: :approved,
                             approved_until: EmbargoRequest.toronto_today,
                             decided_at: Time.current, decided_by: create(:user))

    assert defined?(DspaceExporter), 'rake export selector must centralize embargo eligibility'
    assert_equal [eligible.id], DspaceExporter.theses_for(thesis_id: eligible.id).ids
    assert_empty DspaceExporter.theses_for(thesis_id: pending.id).ids
    assert_empty DspaceExporter.theses_for(thesis_any_id: approved.id).ids
    assert_equal [eligible.id], DspaceExporter.theses_for(publish_date: EmbargoRequest.toronto_today).ids
    assert_equal [eligible.id], DspaceExporter.theses_for.ids
    assert_empty DspaceExporter.theses_for(thesis_id: permanent.id).ids
  end

  should 'rechecks accepted and date constraints immediately before rake deposits' do
    accepted = create(:thesis, status: Thesis::ACCEPTED, published_date: 1.day.ago)
    exporter = RecordingExporter.new

    invoke_rake_export({ 'THESIS' => accepted.id.to_s }, exporter) do |thesis|
      thesis.update_column(:status, Thesis::OPEN)
    end

    assert_empty exporter.deposits

    create(:thesis, status: Thesis::ACCEPTED, published_date: 1.day.ago)
    exporter = RecordingExporter.new

    invoke_rake_export({ 'PUBLISH_DATE' => EmbargoRequest.toronto_today.to_s }, exporter) do |thesis|
      thesis.update_column(:published_date, EmbargoRequest.toronto_today + 1.day)
    end

    assert_empty exporter.deposits

    create(:thesis, status: Thesis::ACCEPTED, published_date: 1.day.ago)
    exporter = RecordingExporter.new

    invoke_rake_export({}, exporter) do |thesis|
      thesis.update_column(:published_date, EmbargoRequest.toronto_today + 1.day)
    end

    assert_empty exporter.deposits
  end

  should 'lets THESIS_ANY bypass status but not an embargo at the rake deposit seam' do
    diagnostic = create(:thesis, status: Thesis::OPEN)
    exporter = RecordingExporter.new

    invoke_rake_export({ 'THESIS_ANY' => diagnostic.id.to_s }, exporter)

    assert_equal 1, exporter.deposits.size

    blocked = create(:thesis, status: Thesis::OPEN)
    create(:submitted_embargo_request, thesis: blocked)
    exporter = RecordingExporter.new

    invoke_rake_export({ 'THESIS_ANY' => blocked.id.to_s }, exporter)

    assert_empty exporter.deposits
  end

  should 'excludes request bound documents from the rake file collector' do
    thesis = create(:thesis)
    primary = create(:document, thesis: thesis, usage: :thesis, supplemental: false,
                                file: Rack::Test::UploadedFile.new('test/fixtures/files/pdf-document.pdf'))
    request = create(:embargo_request, thesis: thesis)
    request_bound = build(:document, thesis: thesis, embargo_request: request,
                                      usage: :thesis, supplemental: true)
    request_bound.save!(validate: false) # Simulate a malformed historical row predating the validation.

    files = send(:extract_thesis_filepaths, thesis)

    assert_includes files, primary.file.path
    assert_not_includes files, request_bound.file.path
  end

  should 'preserve abstract paragraphs and PDF line wraps in serialized export metadata' do
    abstract = "First paragraph with an underlying\ndistribution.\n\n\tSecond paragraph with CO₂ & <research>."
    thesis = build(:thesis, abstract: abstract)

    xml = DspaceExportJob.new.thesis_to_atom_entry(thesis).to_s
    exported = REXML::Document.new(xml).root.elements.to_a.find { |element| element.name == 'abstract' }

    assert_equal abstract, exported.text
    assert_equal abstract, thesis.abstract
  end

  should 'export comma- and semicolon-separated keywords with capitalized first words' do
    thesis = build(:thesis, keywords: 'aeronomy, already Capitalized; “design”')

    values = DspaceExportJob.new.thesis_to_atom_entry(thesis).extensions.to_a
                    .select { |extension| extension.name == 'relationSubjectKeywords' }
                    .map(&:text)

    assert_equal ['Aeronomy', 'Already Capitalized', '“Design”'], values
  end

  should 'add licences after every complete deposit without a production flag' do
    AppSettings.dspace_rest_api_url = 'https://repository.example/server/api'
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    export_log = create(:export_log, production_export: false, complete_thesis: true, publish_thesis: true,
                                     theses_count: 1, theses_ids: thesis.id.to_s)
    job = DspaceExportJob.new
    job.exporter = SuccessfulExporter.new
    job.sleep_interval = 0

    assert_enqueued_with(job: DspaceLicenseBundleJob) { job.perform(export_log.id) }
  end

  should 'always complete the deposit and mark the thesis published' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    export_log = create(:export_log, complete_thesis: false, publish_thesis: false,
                                     theses_count: 1, theses_ids: thesis.id.to_s)
    exporter = RecordingExporter.new
    job = DspaceExportJob.new
    job.exporter = exporter
    job.sleep_interval = 0

    job.perform(export_log.id)

    assert_equal [true], exporter.deposits.map { |deposit| deposit[:complete] }
    assert_equal Thesis::PUBLISHED, thesis.reload.status
  end

  should 'not deposit an export that was cancelled before it started' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    export_log = create(:export_log, job_status: ExportLog::JOB_CANCELLED, theses_count: 1,
                                     theses_ids: thesis.id.to_s)
    exporter = RecordingExporter.new
    job = DspaceExportJob.new
    job.exporter = exporter

    job.perform(export_log.id)

    assert_empty exporter.deposits
    assert_equal ExportLog::JOB_CANCELLED, export_log.reload.job_status
  end

  should 'mark the export failed with the reason when YorkSpace cannot be reached' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    export_log = create(:export_log, theses_count: 1, theses_ids: thesis.id.to_s)
    job = DspaceExportJob.new
    job.exporter = UnreachableExporter.new

    job.perform(export_log.id)

    export_log.reload
    assert_equal ExportLog::JOB_FAILED, export_log.job_status
    assert_includes export_log.output_error, '401 Unauthorized'
    assert_not_nil export_log.job_completed_at
    assert_equal Thesis::ACCEPTED, thesis.reload.status
  end

  should 'keep going after one failed thesis and record times and a plain summary' do
    first = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    second = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    export_log = create(:export_log, theses_count: 2, theses_ids: [first.id, second.id].join(','))
    job = DspaceExportJob.new
    job.exporter = FailingSecondExporter.new
    job.sleep_interval = 0

    job.perform(export_log.id)

    export_log.reload
    assert_equal ExportLog::JOB_DONE, export_log.job_status
    assert_equal [1, 1], [export_log.successful_count, export_log.failed_count]
    assert_includes export_log.output_full, 'Deposited 1 of 2 theses. Failed: 1.'
    assert_not_nil export_log.job_started_at
    assert_not_nil export_log.job_completed_at
  end

  should 'hold a thesis for checking when a send fails after YorkSpace made the item' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    receipt = RECEIPT.new(201, 'Created', 'https://ys.example/swordv2/edit/half', nil)
    export_log = run_export([thesis], FailingExporter.new(ETD::Exporter::PartialDeposit.new('upload failed', receipt)))

    attempt = ThesisDepositAttempt.find_by!(thesis:, export_log:)
    assert_equal ThesisDepositAttempt::NEEDS_CHECKING, attempt.state
    assert_equal 'https://ys.example/swordv2/edit/half', attempt.sword_location
    assert_equal Thesis::ACCEPTED, thesis.reload.status
    assert_equal [0, 0, 1], [export_log.successful_count, export_log.failed_count, export_log.needs_checking_count]
  end

  should 'hold a thesis for checking when the send result is unknown' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    export_log = run_export([thesis], FailingExporter.new(Net::ReadTimeout.new))

    assert_equal ThesisDepositAttempt::NEEDS_CHECKING, ThesisDepositAttempt.find_by!(thesis:).state
    assert_equal 1, export_log.needs_checking_count
  end

  should 'not send a held thesis again in a later export' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    run_export([thesis], FailingExporter.new(Net::ReadTimeout.new))
    exporter = RecordingExporter.new

    later = run_export([thesis], exporter)

    assert_empty exporter.deposits
    assert_equal ThesisDepositAttempt::HELD, ThesisDepositAttempt.find_by!(export_log: later).state
    assert_equal 1, later.needs_checking_count
  end

  should 'leave a refused thesis free to be sent by a later export' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    first = run_export([thesis], FailingExporter.new(ETD::Exporter::NothingSent.new('server returned code 500')))
    exporter = RecordingExporter.new

    run_export([thesis], exporter)

    assert_equal ThesisDepositAttempt::FAILED, ThesisDepositAttempt.find_by!(export_log: first).state
    assert_equal 1, exporter.deposits.size
    assert_equal Thesis::PUBLISHED, thesis.reload.status
  end

  should 'carry on to the next thesis after a YorkSpace library error' do
    first = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    second = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    exporter = FailingExporter.new(Sword2Ruby::Exception.new('server returned 500'))

    export_log = run_export([first, second], exporter)

    assert_equal 2, exporter.calls
    assert_equal ExportLog::JOB_DONE, export_log.job_status
    assert_equal [1, 1], [export_log.successful_count, export_log.needs_checking_count]
  end

  should 'hold a deposited thesis for checking when it cannot be marked published' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    Thesis.any_instance.stubs(:publish).returns(false)

    export_log = run_export([thesis], RecordingExporter.new)

    assert_equal ThesisDepositAttempt::NEEDS_CHECKING, ThesisDepositAttempt.find_by!(thesis:).state
    assert_equal [0, 1], [export_log.successful_count, export_log.needs_checking_count]
  end

  should 'stop before the next thesis once the export is no longer running' do
    first = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    second = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    export_log = create(:export_log, theses_count: 2, theses_ids: [first.id, second.id].join(','))
    exporter = RequestingExporter.new do
      ExportLog.where(id: export_log.id).update_all(job_status: ExportLog::JOB_CANCELLED, active_slot: nil)
    end
    job = DspaceExportJob.new
    job.exporter = exporter
    job.sleep_interval = 0

    job.perform(export_log.id)

    assert_equal 1, exporter.deposited_count
    assert_equal ExportLog::JOB_CANCELLED, export_log.reload.job_status
  end

  should 'say licences need attention when the licence handoff fails' do
    AppSettings.dspace_rest_api_url = 'https://repository.example/server/api'
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    DspaceDeposit.stubs(:find_or_initialize_by).raises('licence state unavailable')

    export_log = run_export([thesis], SuccessfulExporter.new)

    assert_includes export_log.licence_summary, 'Licences need attention for 1 thesis'
  end

  should 'say nothing was sent, and why, when YorkSpace cannot be reached' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)

    export_log = run_export([thesis], UnreachableExporter.new)

    assert_includes export_log.stop_reason, 'could not connect to YorkSpace'
    assert_nil export_log.active_slot
  end

  should 'keep the log under its size limit on a big export' do
    first = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    second = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    export_log = create(:export_log, theses_count: 2, theses_ids: [first.id, second.id].join(','))
    # Just under MySQL's TEXT limit (65,535 bytes), so the test also runs on MySQL in CI.
    export_log.update_columns(output_full: 'x' * 65_000, output_error: 'y' * 65_000)
    job = DspaceExportJob.new
    job.exporter = FailingExporter.new(ETD::Exporter::NothingSent.new('server returned code 500'), on_call: 2)
    job.sleep_interval = 0

    job.perform(export_log.id)

    export_log.reload
    assert_operator export_log.output_full.bytesize, :<=, DspaceExportJob::TEXT_LIMIT
    assert_operator export_log.output_error.bytesize, :<=, DspaceExportJob::TEXT_LIMIT
    assert_includes export_log.output_full, 'Deposited 1 of 2 theses.'
    assert_includes export_log.output_error, 'server returned code 500'
    assert_equal ExportLog::JOB_DONE, export_log.job_status
  end

  should 'finish every thesis even when the log cannot be written' do
    first = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    second = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    DspaceExportJob.any_instance.stubs(:write_text).raises(ActiveRecord::ValueTooLong, 'Data too long')

    export_log = run_export([first, second], RecordingExporter.new)

    assert_equal ExportLog::JOB_DONE, export_log.job_status
    assert_equal 2, export_log.successful_count
    assert_equal [Thesis::PUBLISHED] * 2, [first.reload.status, second.reload.status]
  end

  should 'store an error message with characters the database tables cannot hold' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)

    export_log = run_export([thesis], FailingExporter.new(ETD::Exporter::NothingSent.new("refused \u{1F600} item")))

    attempt = ThesisDepositAttempt.find_by!(thesis:)
    assert_equal ThesisDepositAttempt::FAILED, attempt.state
    assert_not_includes attempt.error_message, "\u{1F600}"
    assert_not_includes export_log.output_error, "\u{1F600}"
  end

  should 'list a thesis whose send could not be recorded at all' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    ThesisDepositAttempt.any_instance.stubs(:needs_checking!).raises(ActiveRecord::StatementInvalid, 'write failed')

    export_log = run_export([thesis], FailingExporter.new(Net::ReadTimeout.new))

    assert_equal [thesis.id], export_log.theses_needing_checking.ids
    assert_equal thesis.id, ThesisDepositAttempt.find_by!(thesis:).open_thesis_id
  end

  should 'free the export slot when it finishes' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)

    export_log = run_export([thesis], RecordingExporter.new)

    assert_nil export_log.active_slot
    assert_equal ThesisDepositAttempt::SENT, ThesisDepositAttempt.find_by!(thesis:).state
    assert_nil ThesisDepositAttempt.find_by!(thesis:).open_thesis_id
  end

  private

  def run_export(theses, exporter)
    export_log = create(:export_log, theses_count: theses.size, theses_ids: theses.map(&:id).join(','))
    job = DspaceExportJob.new
    job.exporter = exporter
    job.sleep_interval = 0
    job.perform(export_log.id)
    export_log.reload
  end

  def invoke_rake_export(environment, exporter, &before_deposit)
    saved_environment = %w[THESIS THESIS_ANY PUBLISH_DATE ZIPPED COMPLETE_THESIS PUBLISH PRIMARY_FILES_ONLY].to_h do |key|
      [key, ENV[key]]
    end
    original_atom_builder = Object.instance_method(:thesis_to_atom_entry)
    ENV.delete('THESIS')
    ENV.delete('THESIS_ANY')
    ENV.delete('PUBLISH_DATE')
    environment.each { |key, value| ENV[key] = value }
    ETD::Exporter.stubs(:new).returns(exporter)
    Kernel.stubs(:sleep)

    if before_deposit
      Object.send(:define_method, :thesis_to_atom_entry) do |thesis|
        entry = original_atom_builder.bind_call(self, thesis)
        before_deposit.call(thesis)
        entry
      end
      Object.send(:private, :thesis_to_atom_entry)
    end

    Rake::Task['dspace:export'].reenable
    Rake::Task['dspace:export'].invoke
  ensure
    Object.send(:define_method, :thesis_to_atom_entry, original_atom_builder) if original_atom_builder
    Object.send(:private, :thesis_to_atom_entry) if original_atom_builder
    saved_environment&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    Rake::Task['dspace:export'].reenable
  end

  should 'enqueue a separate licence job after a completed production SWORD deposit' do
    AppSettings.dspace_rest_api_url = 'https://repository.example/server/api'
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    export_log = create(
      :export_log,
      production_export: true,
      complete_thesis: true,
      theses_count: 1,
      theses_ids: thesis.id.to_s
    )
    job = DspaceExportJob.new
    job.exporter = SuccessfulExporter.new
    job.sleep_interval = 0

    assert_enqueued_with(job: DspaceLicenseBundleJob) do
      job.perform(export_log.id)
    end

    deposit = DspaceDeposit.find_by!(export_log:, thesis:)
    assert_equal '22222222-2222-4222-8222-222222222222', deposit.item_uuid
    assert_equal DspaceDeposit::PENDING, deposit.license_status
    assert_equal 1, export_log.reload.successful_count
    assert_equal 0, export_log.failed_count
  end

  should 'keep a successful SWORD deposit successful when licence setup fails' do
    AppSettings.dspace_rest_api_url = 'https://repository.example/server/api'
    thesis = create(:thesis, status: Thesis::ACCEPTED, published_date: 3.months.ago)
    export_log = create(
      :export_log,
      production_export: true,
      complete_thesis: true,
      theses_count: 1,
      theses_ids: thesis.id.to_s
    )
    job = DspaceExportJob.new
    job.exporter = SuccessfulExporter.new
    job.sleep_interval = 0
    DspaceDeposit.stubs(:find_or_initialize_by).raises('licence state unavailable')

    job.perform(export_log.id)

    export_log.reload
    assert_equal 1, export_log.successful_count
    assert_equal 0, export_log.failed_count
    assert_equal ExportLog::JOB_DONE, export_log.job_status
    assert_includes export_log.output_full, 'LICENSE POST-DEPOSIT SETUP ERROR: licence state unavailable'
  end
end
