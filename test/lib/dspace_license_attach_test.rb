# frozen_string_literal: true

require 'test_helper'
require 'digest'
require 'json'
require 'stringio'
require 'tmpdir'
require 'etd/dspace_license_attach'
require 'etd/ensure_license_bundle'
require 'etd/license_files'
require_relative '../support/sqlite_license_lock'

class DspaceLicenseAttachTest < ActiveSupport::TestCase
  include SqliteLicenseLock

  ITEM_UUID = '22222222-2222-4222-8222-222222222222'
  OTHER_UUID = '33333333-3333-4333-8333-333333333333'
  COLLECTION_UUID = '11111111-1111-4111-8111-111111111111'
  OUTSIDE_UUID = '44444444-4444-4444-8444-444444444444'
  PRODUCTION_UUID = '9eb3679d-898f-4180-9335-bd3211dd87fb'

  setup do
    @directory = Dir.mktmpdir('license-attach')
    @ids_path = File.join(@directory, 'ids.txt')
    @output = StringIO.new
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  should 'reject an invalid uuid before calling YorkSpace' do
    File.write(@ids_path, "not-a-uuid\n")
    client = AttachClient.new

    error = assert_raises(ETD::DspaceLicenseAttach::InputError) do
      attach(client).run(ids_path: @ids_path)
    end

    assert_match(/Invalid item UUID/, error.message)
    assert_empty client.calls
    assert_empty @output.string
  end

  should 'reject duplicate ids before calling YorkSpace' do
    File.write(@ids_path, "#{ITEM_UUID}\n#{ITEM_UUID.upcase}\n")
    client = AttachClient.new

    error = assert_raises(ETD::DspaceLicenseAttach::InputError) do
      attach(client).run(ids_path: @ids_path)
    end

    assert_match(/Duplicate/, error.message)
    assert_empty client.calls
  end

  should 'refuse apply mode without confirmation, a results path, credentials, or MySQL' do
    error = assert_raises(ETD::DspaceLicenseAttach::InputError) do
      ETD::DspaceLicenseAttach.validate_invocation!(
        apply: true, confirm: nil, results_path: nil, username: nil, password: nil, adapter_name: 'SQLite'
      )
    end
    assert_match(/CONFIRM=ATTACH_LICENSES/, error.message)

    error = assert_raises(ETD::DspaceLicenseAttach::InputError) do
      ETD::DspaceLicenseAttach.validate_invocation!(
        apply: true, confirm: 'ATTACH_LICENSES', results_path: nil, username: 'user', password: 'secret',
        adapter_name: 'Mysql2'
      )
    end
    assert_match(/RESULTS_PATH/, error.message)

    error = assert_raises(ETD::DspaceLicenseAttach::InputError) do
      ETD::DspaceLicenseAttach.validate_invocation!(
        apply: true, confirm: 'ATTACH_LICENSES', results_path: 'out.jsonl', username: nil, password: nil,
        adapter_name: 'Mysql2'
      )
    end
    assert_match(/username and password/, error.message)

    error = assert_raises(ETD::DspaceLicenseAttach::InputError) do
      ETD::DspaceLicenseAttach.validate_invocation!(
        apply: true, confirm: 'ATTACH_LICENSES', results_path: 'out.jsonl', username: 'user', password: 'secret',
        adapter_name: 'SQLite'
      )
    end
    assert_match(/MySQL/, error.message)
  end

  should 'leave an item outside the ETD community unchanged' do
    File.write(@ids_path, "#{ITEM_UUID}\n")
    client = AttachClient.new(owning: { ITEM_UUID => OUTSIDE_UUID })
    bundle = RecordingBundle.new

    summary = attach(client, bundle:).run(ids_path: @ids_path)

    assert_equal 1, summary.fetch(:out_of_scope)
    assert_empty bundle.calls
    assert_equal false, ETD::DspaceLicenseAttach.successful?(summary)
    assert_equal 'out_of_scope', record.fetch('status')
  end

  should 'treat a mapped collection in the community as in scope' do
    File.write(@ids_path, "#{ITEM_UUID}\n")
    client = AttachClient.new(owning: { ITEM_UUID => OUTSIDE_UUID }, mapped: { ITEM_UUID => [COLLECTION_UUID] })
    bundle = RecordingBundle.new

    summary = attach(client, bundle:).run(ids_path: @ids_path)

    assert_equal 1, summary.fetch(:dry_run)
    assert_equal [[ITEM_UUID, true]], bundle.calls
    assert_equal true, ETD::DspaceLicenseAttach.successful?(summary)
  end

  should 'call the licence service in apply mode and record the upload' do
    File.write(@ids_path, "#{ITEM_UUID}\n")
    client = AttachClient.new
    uploaded = [{ name: 'license.txt', uuid: '55555555-5555-4555-8555-555555555555' }]
    bundle = RecordingBundle.new(status: :updated, uploaded_bitstreams: uploaded, bundle_uuid: COLLECTION_UUID)

    summary = attach(client, apply: true, bundle:).run(ids_path: @ids_path)

    assert_equal [[ITEM_UUID, false]], bundle.calls
    assert_equal 1, summary.fetch(:updated)
    assert_equal true, summary.fetch(:apply)
    assert_equal uploaded.map(&:stringify_keys), record.fetch('uploaded_bitstreams')
  end

  should 'record a conflicting bitstream as review required' do
    File.write(@ids_path, "#{ITEM_UUID}\n")
    client = AttachClient.new
    bundle = RecordingBundle.new(error: ETD::EnsureLicenseBundle::ConflictError.new('LICENSE bitstream differs'))

    summary = attach(client, apply: true, bundle:).run(ids_path: @ids_path)

    assert_equal 1, summary.fetch(:review_required)
    assert_equal false, ETD::DspaceLicenseAttach.successful?(summary)
    assert_match(/differs/, record.fetch('error'))
  end

  should 'abort a local payload failure before writing an item record' do
    File.write(@ids_path, "#{ITEM_UUID}\n")
    client = AttachClient.new
    bundle = RecordingBundle.new(error: ETD::EnsureLicenseBundle::PayloadError.new('Local licence payload failed'))

    assert_raises(ETD::EnsureLicenseBundle::PayloadError) do
      attach(client, apply: true, bundle:).run(ids_path: @ids_path)
    end

    assert_empty @output.string
  end

  should 'perform no upload when the canonical files are already present' do
    File.write(@ids_path, "#{ITEM_UUID}\n")
    client = CompleteItemClient.new(item_uuid: ITEM_UUID, collection_uuid: COLLECTION_UUID)

    summary = attach(client, apply: true).run(ids_path: @ids_path)

    assert_equal 1, summary.fetch(:complete)
    assert_empty client.writes
    assert_equal 'complete', record.fetch('status')
  end

  def attach(client, apply: false, bundle: nil)
    options = { client:, output: @output, apply: }
    options[:bundle_factory] = ->(_rest_client) { bundle } if bundle
    ETD::DspaceLicenseAttach.new(**options)
  end

  def record
    JSON.parse(@output.string.lines.first)
  end

  class AttachClient
    attr_reader :calls, :base_url

    def initialize(owning: nil, mapped: nil)
      @owning = owning || {}
      @mapped = mapped || {}
      @calls = []
      @base_url = 'https://yorkspace.library.yorku.ca/server/api'
    end

    def find_handle(_handle)
      @calls << :find_handle
      { 'uuid' => DspaceLicenseAttachTest::PRODUCTION_UUID, 'handle' => '10315/26310', 'type' => 'community' }
    end

    def community_collection_uuids(_community_uuid)
      @calls << :collections
      [DspaceLicenseAttachTest::COLLECTION_UUID]
    end

    def owning_collection_uuid(item_uuid)
      @calls << :owning
      @owning.fetch(item_uuid, DspaceLicenseAttachTest::COLLECTION_UUID)
    end

    def mapped_collection_uuids(item_uuid)
      @calls << :mapped
      @mapped.fetch(item_uuid, [])
    end
  end

  class RecordingBundle
    attr_reader :calls

    def initialize(status: :dry_run, missing_files: ['license.txt'], uploaded_bitstreams: [], bundle_uuid: nil,
                   error: nil)
      @status = status
      @missing_files = missing_files
      @uploaded_bitstreams = uploaded_bitstreams
      @bundle_uuid = bundle_uuid
      @error = error
      @calls = []
    end

    def call(item_uuid:, dry_run:)
      @calls << [item_uuid, dry_run]
      raise @error if @error

      ETD::EnsureLicenseBundle::Result.new(
        status: @status,
        missing_files: @missing_files,
        bundle_uuid: @bundle_uuid,
        uploaded_bitstreams: @uploaded_bitstreams
      )
    end
  end

  class CompleteItemClient < AttachClient
    attr_reader :writes

    def initialize(item_uuid:, collection_uuid:)
      super()
      @item_uuid = item_uuid
      @collection_uuid = collection_uuid
      @writes = []
      @bitstreams = ETD::LicenseFiles.canonical.map do |file|
        {
          'uuid' => SecureRandom.uuid,
          'name' => file.fetch(:name),
          'sizeBytes' => File.size(file.fetch(:path)),
          'checkSum' => { 'checkSumAlgorithm' => 'MD5', 'value' => Digest::MD5.file(file.fetch(:path)).hexdigest }
        }
      end
    end

    def bundles(_item_uuid)
      [{ 'uuid' => @collection_uuid, 'name' => 'LICENSE' }]
    end

    def bitstreams(_bundle_uuid)
      @bitstreams
    end

    def create_bundle(*)
      @writes << :create_bundle
    end

    def upload_bitstream(*)
      @writes << :upload_bitstream
    end
  end
end
