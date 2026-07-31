# frozen_string_literal: true

require 'test_helper'
require 'rake'

extend Rake::DSL

load Rails.root.join('lib/tasks/dspace_exporter.rake').to_s

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
end
