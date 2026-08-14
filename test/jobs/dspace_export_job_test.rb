# frozen_string_literal: true

require 'test_helper'

class DspaceExportJobTest < ActiveSupport::TestCase
  class ExporterDouble
    attr_reader :deposits
    attr_reader :prepared

    def initialize(outcomes = [])
      @outcomes = outcomes
      @deposits = []
      @prepared = false
    end

    def prepare_collection
      @prepared = true
    end

    def deposit(**options)
      @deposits << options
      outcome = @outcomes.shift
      raise outcome if outcome.is_a?(Exception)

      OpenStruct.new(status_code: 201, status_message: 'Deposited')
    end
  end

  setup do
    @job = DspaceExportJob.new
    @job.sleep_interval = 0
  end

  should 'return without doing work when the export log no longer exists' do
    assert_nil @job.perform(-1)
  end

  should 'map supported language names to ISO codes and unknown values to other' do
    assert_equal 'en', @job.language_to_iso('English')
    assert_equal 'en', @job.language_to_iso('ENG')
    assert_equal 'fr', @job.language_to_iso('french')
    assert_equal 'other', @job.language_to_iso(nil)
    assert_equal 'other', @job.language_to_iso('Spanish')
  end

  should 'return the final program segment for DSpace metadata' do
    assert_equal 'Psychology', @job.short_program_name('GS MA PSYC., Psychology')
    assert_equal 'Psychology', @job.short_program_name('Psychology')
    assert_nil @job.short_program_name(nil)
  end

  should 'map thesis metadata into the Atom entry' do
    thesis = create(:thesis, title: 'My Thesis', author: 'Jane Doe', supervisor: 'Dr X',
                             language: 'English', degree_name: 'MA', degree_level: Thesis::MASTERS,
                             program: 'GS MA PSYC., Psychology', exam_date: Date.new(2024, 1, 2),
                             keywords: 'one, two')
    thesis.loc_subjects << create(:loc_subject, name: 'Library science')

    values = @job.thesis_to_atom_entry(thesis).extensions.to_a.group_by(&:name).transform_values { |extensions| extensions.map(&:text) }

    assert_equal ['My Thesis'], values['title']
    assert_equal ['Jane Doe'], values['creator']
    assert_equal ['Library science'], values['subject']
    assert_equal %w[one two], values['relationSubjectKeywords']
    assert_equal ['en'], values['language']
    assert_equal ['Psychology'], values['discipline']
    assert_equal ['2024-01-02'], values['dateCopyrighted']
  end

  should 'extract only active document paths and handle a missing thesis' do
    thesis = create(:thesis)
    active = create(:document, thesis: thesis)
    create(:document, thesis: thesis, deleted: true)

    assert_equal [active.file.path], @job.extract_thesis_filepaths(thesis)
    assert_equal [], @job.extract_thesis_filepaths(nil)
  end

  should 'mark an export with no theses as done' do
    export_log = create(:export_log, theses_count: 0)
    exporter = ExporterDouble.new
    @job.exporter = exporter

    @job.perform(export_log.id)

    assert_equal ExportLog::JOB_DONE, export_log.reload.job_status
    assert_not exporter.prepared
  end

  should 'record a successful deposit and publish when requested' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, embargoed: false)
    export_log = create(:export_log, theses_count: 1, theses_ids: thesis.id.to_s, publish_thesis: true)
    exporter = ExporterDouble.new
    @job.exporter = exporter

    @job.perform(export_log.id)

    export_log.reload
    assert_equal ExportLog::JOB_DONE, export_log.job_status
    assert_equal 1, export_log.successful_count
    assert_equal thesis.id.to_s, export_log.successful_ids
    assert_equal 0, export_log.failed_count
    assert_equal Thesis::PUBLISHED, thesis.reload.status
    assert exporter.prepared
    assert_equal 1, exporter.deposits.size
  end

  should 'mark an export as failed and record the deposit error' do
    thesis = create(:thesis, status: Thesis::ACCEPTED, embargoed: false)
    export_log = create(:export_log, theses_count: 1, theses_ids: thesis.id.to_s)
    exporter = ExporterDouble.new([StandardError.new('network down')])
    @job.exporter = exporter

    @job.perform(export_log.id)

    export_log.reload
    assert_equal ExportLog::JOB_FAILED, export_log.job_status
    assert_equal 1, export_log.failed_count
    assert_equal thesis.id.to_s, export_log.failed_ids
    assert_includes export_log.output_error, 'network down'
    assert_equal 0, export_log.successful_count
  end

  should 'finish as done when at least one thesis succeeds in a mixed export' do
    first = create(:thesis, status: Thesis::ACCEPTED, embargoed: false)
    second = create(:thesis, status: Thesis::ACCEPTED, embargoed: false)
    export_log = create(:export_log, theses_count: 2, theses_ids: "#{first.id},#{second.id}")
    exporter = ExporterDouble.new([nil, StandardError.new('second deposit failed')])
    @job.exporter = exporter

    @job.perform(export_log.id)

    export_log.reload
    assert_equal ExportLog::JOB_DONE, export_log.job_status
    assert_equal 1, export_log.successful_count
    assert_equal 1, export_log.failed_count
    assert_equal first.id.to_s, export_log.successful_ids
    assert_equal second.id.to_s, export_log.failed_ids
  end
end
