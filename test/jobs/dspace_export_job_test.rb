# frozen_string_literal: true

require 'test_helper'

class DspaceExportJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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
    primary = create(:document, thesis:, supplemental: false,
                                file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))
    supplemental = create(:document, thesis:, supplemental: true,
                                     file: fixture_file_upload('pdf-document.pdf'))
    licence = create(:document_licence, thesis:)
    embargo = create(:document, thesis:, supplemental: true, usage: :embargo,
                                file: fixture_file_upload('pdf-document.pdf'))
    modification_request = create(:document, thesis:, supplemental: true, usage: :modification_request,
                                             file: fixture_file_upload('document-microsoft.doc'))

    paths = DspaceExportJob.new.extract_thesis_filepaths(thesis)

    assert_includes paths, primary.file.path
    assert_includes paths, supplemental.file.path
    assert_not_includes paths, licence.file.path
    assert_not_includes paths, embargo.file.path
    assert_not_includes paths, modification_request.file.path
  end

  should 'export only primary and thesis supplemental files from the latest submission snapshot' do
    thesis = create(:thesis)
    primary = create(:document, thesis:, supplemental: false,
                                file: fixture_file_upload('Tony_Rich_E_2012_Phd.pdf'))
    supplemental = create(:document, thesis:, supplemental: true,
                                     file: fixture_file_upload('pdf-document.pdf'))
    licence = create(:document_licence, thesis:)
    embargo = create(:document, thesis:, supplemental: true, usage: :embargo,
                                file: fixture_file_upload('pdf-document.pdf'))
    modification_request = create(:document, thesis:, supplemental: true, usage: :modification_request,
                                             file: fixture_file_upload('document-microsoft.doc'))
    version = thesis.create_submission_snapshot!(thesis.student)

    snapshots = version.submission_documents.index_by(&:source_document_id)
    paths = DspaceExportJob.new.extract_thesis_filepaths(thesis)

    assert_includes paths, snapshots.fetch(primary.id).file.path
    assert_includes paths, snapshots.fetch(supplemental.id).file.path
    assert_not_includes paths, snapshots.fetch(licence.id).file.path
    assert_not_includes paths, snapshots.fetch(embargo.id).file.path
    assert_not_includes paths, snapshots.fetch(modification_request.id).file.path
  end

  should 'enqueue a separate licence job after a completed production SWORD deposit' do
    AppSettings.dspace_rest_api_url = 'https://repository.example/server/api'
    thesis = create(:thesis, status: Thesis::ACCEPTED)
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
    thesis = create(:thesis, status: Thesis::ACCEPTED)
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
