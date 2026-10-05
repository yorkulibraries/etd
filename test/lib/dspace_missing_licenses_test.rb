# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'tmpdir'
require 'etd/dspace_missing_licenses'

class DspaceMissingLicensesTest < ActiveSupport::TestCase
  MISSING_UUID = '22222222-2222-4222-8222-222222222222'
  LICENSED_UUID = '33333333-3333-4333-8333-333333333333'
  UNREADABLE_UUID = '44444444-4444-4444-8444-444444444444'
  PRODUCTION_UUID = '9eb3679d-898f-4180-9335-bd3211dd87fb'

  setup do
    @directory = Dir.mktmpdir('missing-licenses')
    @missing_path = File.join(@directory, 'missing.txt')
    @results_path = File.join(@directory, 'scan.jsonl')
    @progress = StringIO.new
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  should 'refuse a different community uuid on production before searching' do
    client = ScanClient.new(
      base_url: 'https://yorkspace.library.yorku.ca/server/api',
      community_uuid: '11111111-1111-4111-8111-111111111111'
    )

    assert_raises(ETD::DspaceEtdCommunity::Error) { scan(client).run }

    assert_empty client.scopes
    refute File.file?(@missing_path)
  end

  should 'write only item ids that have no LICENSE bundle' do
    client = ScanClient.new(
      pages: [[MISSING_UUID, LICENSED_UUID]],
      bundles: { MISSING_UUID => [], LICENSED_UUID => ['ORIGINAL', 'LICENSE'] },
      total_elements: 2
    )

    summary = scan(client).run

    assert_equal true, summary.fetch(:complete)
    assert_equal PRODUCTION_UUID, summary.fetch(:community_uuid)
    assert_equal false, summary.fetch(:authenticated)
    assert_equal 2, summary.fetch(:total_expected)
    assert_equal 1, summary.fetch(:missing)
    assert_equal 1, summary.fetch(:has_license_bundle)
    assert_equal "#{MISSING_UUID}\n", File.read(@missing_path)
    assert_equal [MISSING_UUID, LICENSED_UUID], journal.map { |record| record.fetch('item_uuid') }
    refute client.created
  end

  should 'record HTTP 401 as unreadable and leave that id out of the file' do
    client = ScanClient.new(
      pages: [[UNREADABLE_UUID]],
      errors: { UNREADABLE_UUID => ETD::DspaceRestClient::RequestError.new('DSpace REST GET returned 401', status: 401) },
      total_elements: 1
    )

    summary = scan(client).run

    assert_equal false, summary.fetch(:complete)
    assert_equal 1, summary.fetch(:unreadable)
    assert_equal '', File.read(@missing_path)
    assert_equal 'unreadable', journal.first.fetch('status')
    assert_equal 'DSpace REST GET returned 401', journal.first.fetch('error')
  end

  should 'resume by skipping a settled item and retrying an unreadable item' do
    File.write(@results_path, [
      { command: 'missing', item_uuid: MISSING_UUID, status: 'missing', license_bundle_count: 0 },
      { command: 'missing', item_uuid: UNREADABLE_UUID, status: 'unreadable', error: 'old' }
    ].map { |record| JSON.generate(record) }.join("\n") + "\n")
    client = ScanClient.new(
      pages: [[MISSING_UUID, UNREADABLE_UUID]],
      bundles: { UNREADABLE_UUID => [] },
      total_elements: 2
    )

    summary = scan(client).run

    assert_equal [UNREADABLE_UUID], client.bundle_reads
    assert_equal true, summary.fetch(:complete)
    assert_equal "#{MISSING_UUID}\n#{UNREADABLE_UUID}\n", File.read(@missing_path)
  end

  should 'stay incomplete when discovery returns fewer items than its total' do
    client = ScanClient.new(pages: [[MISSING_UUID]], bundles: { MISSING_UUID => [] }, total_elements: 2)

    summary = scan(client).run

    assert_equal false, summary.fetch(:complete)
    assert_equal "#{MISSING_UUID}\n", File.read(@missing_path)
  end

  should 'replace an existing id file only after the temporary file is ready' do
    File.write(@missing_path, "stale\n")
    client = ScanClient.new(pages: [[MISSING_UUID]], bundles: { MISSING_UUID => [] }, total_elements: 1)

    File.stub(:rename, ->(*) { raise 'disk full' }) { scan(client).run }

    assert_equal "stale\n", File.read(@missing_path)
    assert_equal MISSING_UUID, journal.first.fetch('item_uuid')
  end

  should 'report progress every 100 items' do
    uuids = (1..100).map { |number| format('00000000-0000-4000-8000-%012x', number) }
    client = ScanClient.new(pages: [uuids], bundles: uuids.to_h { |uuid| [uuid, []] }, total_elements: 100)

    scan(client).run

    assert_includes @progress.string, 'checked 100 items'
  end

  def scan(client)
    ETD::DspaceMissingLicenses.new(
      client:,
      missing_path: @missing_path,
      results_path: @results_path,
      progress: @progress
    )
  end

  def journal
    File.readlines(@results_path, chomp: true).map { |line| JSON.parse(line) }
  end

  class ScanClient
    attr_reader :scopes, :bundle_reads, :base_url

    def initialize(base_url: 'https://yorkspace.library.yorku.ca/server/api',
                   community_uuid: DspaceMissingLicensesTest::PRODUCTION_UUID,
                   pages: [], bundles: {}, errors: {}, total_elements: 0)
      @base_url = base_url
      @community_uuid = community_uuid
      @pages = pages
      @bundles = bundles
      @errors = errors
      @total_elements = total_elements
      @scopes = []
      @bundle_reads = []
      @created = false
    end

    def credentials?
      false
    end

    def created
      @created
    end

    def find_handle(_handle)
      { 'uuid' => @community_uuid, 'handle' => '10315/26310', 'type' => 'community' }
    end

    def search_item_uuids(scope_uuid)
      @scopes << scope_uuid
      @pages.each do |uuids|
        yield({ uuids:, total_elements: @total_elements, total_pages: 1 })
      end
    end

    def bundles(item_uuid)
      @bundle_reads << item_uuid
      raise @errors.fetch(item_uuid) if @errors.key?(item_uuid)

      @bundles.fetch(item_uuid).map { |name| { 'name' => name, 'uuid' => item_uuid } }
    end

    def with_transient_retry
      yield
    end

    def create_bundle(*)
      @created = true
    end
  end
end
