# frozen_string_literal: true

require 'test_helper'
require 'rake'

extend Rake::DSL

load Rails.root.join('lib/tasks/dspace_exporter.rake').to_s
Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)

class DspaceExportJobTest < ActiveJob::TestCase
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

  should 'recheck embargo eligibility after an export log captured ids' do
    eligible = create(:thesis, status: Thesis::ACCEPTED)
    newly_blocked = create(:thesis, status: Thesis::ACCEPTED)
    export_log = create(:export_log, theses_ids: [eligible.id, newly_blocked.id].join(','), theses_count: 2)
    create(:submitted_embargo_request, thesis: newly_blocked)

    job = DspaceExportJob.new
    job.export_log = export_log

    assert_equal [eligible.id], job.send(:eligible_theses).pluck(:id)
  end

  should 'rechecks eligibility immediately before each DSpace deposit' do
    first = create(:thesis, status: Thesis::ACCEPTED, title: 'First thesis')
    second = create(:thesis, status: Thesis::ACCEPTED, title: 'Second thesis')
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
    request_bound = create(:document, thesis: thesis, embargo_request: request,
                                       usage: :thesis, supplemental: true)

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
    request_bound = create(:document, thesis: thesis, embargo_request: request,
                                       usage: :thesis, supplemental: true)

    files = send(:extract_thesis_filepaths, thesis)

    assert_includes files, primary.file.path
    assert_not_includes files, request_bound.file.path
  end

  private

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
end
