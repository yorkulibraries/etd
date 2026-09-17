# frozen_string_literal: true

require 'test_helper'
require 'digest'
require 'tmpdir'
require 'etd/ensure_license_bundle'
require_relative '../support/sqlite_license_lock'

class EnsureLicenseBundleTest < ActiveSupport::TestCase
  include SqliteLicenseLock
  class StatefulDspaceClient
    attr_reader :writes

    def initialize(bundles:)
      @bundles = bundles
      @writes = []
    end

    def bundles(_item_uuid)
      @bundles.map { |bundle| bundle.reject { |key, _value| key == 'bitstreams' } }
    end

    def bitstreams(bundle_uuid)
      @bundles.find { |bundle| bundle.fetch('uuid') == bundle_uuid }.fetch('bitstreams')
    end

    def create_bundle(item_uuid, name:)
      bundle = { 'uuid' => SecureRandom.uuid, 'name' => name, 'bitstreams' => [] }
      @bundles << bundle
      @writes << { action: :create_bundle, item_uuid:, name: }
      bundle.reject { |key, _value| key == 'bitstreams' }
    end

    def upload_bitstream(bundle_uuid, file_path:, name:)
      contents = File.binread(file_path)
      bitstream = {
        'uuid' => SecureRandom.uuid,
        'name' => name,
        'sizeBytes' => contents.bytesize,
        'checkSum' => {
          'checkSumAlgorithm' => 'MD5',
          'value' => Digest::MD5.hexdigest(contents)
        }
      }
      @bundles.find { |bundle| bundle.fetch('uuid') == bundle_uuid }.fetch('bitstreams') << bitstream
      @writes << { action: :upload_bitstream, bundle_uuid:, name: }
      bitstream
    end
  end

  setup do
    @directory = Dir.mktmpdir('etd-license-test')
    @files = [
      write_license('license.txt', "first licence\n"),
      write_license('YorkU_ETDlicense.txt', "second licence\n")
    ]
  end

  teardown do
    FileUtils.remove_entry(@directory)
  end

  should 'leave an already complete LICENSE bundle unchanged' do
    bundle_uuid = '11111111-1111-4111-8111-111111111111'
    client = StatefulDspaceClient.new(
      bundles: [
        {
          'uuid' => bundle_uuid,
          'name' => 'LICENSE',
          'bitstreams' => @files.map do |file|
            {
              'uuid' => SecureRandom.uuid,
              'name' => file.fetch(:name),
              'sizeBytes' => file.fetch(:size),
              'checkSum' => {
                'checkSumAlgorithm' => 'MD5',
                'value' => file.fetch(:md5)
              }
            }
          end
        }
      ]
    )

    result = ETD::EnsureLicenseBundle.new(client:, files: @files).call(
      item_uuid: '22222222-2222-4222-8222-222222222222'
    )

    assert_equal :complete, result.status
    assert_empty result.missing_files
    assert_empty client.writes
  end

  should 'report an already complete LICENSE bundle as complete during a dry run' do
    bundle_uuid = '11111111-1111-4111-8111-111111111111'
    client = StatefulDspaceClient.new(
      bundles: [
        {
          'uuid' => bundle_uuid,
          'name' => 'LICENSE',
          'bitstreams' => @files.map do |file|
            {
              'uuid' => SecureRandom.uuid,
              'name' => file.fetch(:name),
              'sizeBytes' => file.fetch(:size),
              'checkSum' => { 'checkSumAlgorithm' => 'MD5', 'value' => file.fetch(:md5) }
            }
          end
        }
      ]
    )

    result = ETD::EnsureLicenseBundle.new(client:, files: @files).call(
      item_uuid: '22222222-2222-4222-8222-222222222222',
      dry_run: true
    )

    assert_equal :complete, result.status
    assert_empty result.missing_files
    assert_empty client.writes
  end

  should 'report missing files without writing during a dry run' do
    client = StatefulDspaceClient.new(bundles: [])

    result = ETD::EnsureLicenseBundle.new(client:, files: @files).call(
      item_uuid: '22222222-2222-4222-8222-222222222222',
      dry_run: true
    )

    assert_equal :dry_run, result.status
    assert_equal ['license.txt', 'YorkU_ETDlicense.txt'], result.missing_files
    assert_nil result.bundle_uuid
    assert_empty client.writes
  end

  should 'stop when a canonical filename has different bytes' do
    bundle_uuid = '11111111-1111-4111-8111-111111111111'
    bitstreams = @files.map do |file|
      {
        'uuid' => SecureRandom.uuid,
        'name' => file.fetch(:name),
        'sizeBytes' => file.fetch(:size),
        'checkSum' => {
          'checkSumAlgorithm' => 'MD5',
          'value' => file.fetch(:md5)
        }
      }
    end
    bitstreams.first['checkSum']['value'] = Digest::MD5.hexdigest('different bytes')
    client = StatefulDspaceClient.new(
      bundles: [{ 'uuid' => bundle_uuid, 'name' => 'LICENSE', 'bitstreams' => bitstreams }]
    )

    error = assert_raises(ETD::EnsureLicenseBundle::ConflictError) do
      ETD::EnsureLicenseBundle.new(client:, files: @files).call(
        item_uuid: '22222222-2222-4222-8222-222222222222',
        dry_run: true
      )
    end

    assert_match(/license\.txt/, error.message)
    assert_empty client.writes
  end

  should 'create a missing LICENSE bundle and verify each uploaded file' do
    item_uuid = '22222222-2222-4222-8222-222222222222'
    client = StatefulDspaceClient.new(bundles: [])

    result = ETD::EnsureLicenseBundle.new(client:, files: @files).call(item_uuid:)

    assert_equal :updated, result.status
    assert_empty result.missing_files
    assert_match(/\A[0-9a-f-]{36}\z/, result.bundle_uuid)
    assert_equal ['license.txt', 'YorkU_ETDlicense.txt'],
                 result.uploaded_bitstreams.map { |bitstream| bitstream.fetch(:name) }
    result.uploaded_bitstreams.each do |bitstream|
      assert_match(/\A[0-9a-f-]{36}\z/, bitstream.fetch(:uuid))
    end
    assert_equal [
      { action: :create_bundle, item_uuid:, name: 'LICENSE' },
      { action: :upload_bitstream, bundle_uuid: result.bundle_uuid, name: 'license.txt' },
      { action: :upload_bitstream, bundle_uuid: result.bundle_uuid, name: 'YorkU_ETDlicense.txt' }
    ], client.writes
    assert_equal ['license.txt', 'YorkU_ETDlicense.txt'],
                 client.bitstreams(result.bundle_uuid).map { |bitstream| bitstream.fetch('name') }
  end

  should 'refuse to operate when a local payload differs from its approved manifest' do
    File.binwrite(@files.first.fetch(:path), 'tampered')
    client = StatefulDspaceClient.new(bundles: [])

    error = assert_raises(ETD::EnsureLicenseBundle::PayloadError) do
      ETD::EnsureLicenseBundle.new(client:, files: @files).call(
        item_uuid: '22222222-2222-4222-8222-222222222222',
        dry_run: true
      )
    end

    assert_match(/license\.txt/, error.message)
    assert_empty client.writes
  end

  should 'refuse to operate when a local payload SHA-256 differs from its approved manifest' do
    files = @files.map(&:dup)
    files.first[:sha256] = Digest::SHA256.hexdigest('different bytes')
    client = StatefulDspaceClient.new(bundles: [])

    error = assert_raises(ETD::EnsureLicenseBundle::PayloadError) do
      ETD::EnsureLicenseBundle.new(client:, files:).call(
        item_uuid: '22222222-2222-4222-8222-222222222222',
        dry_run: true
      )
    end

    assert_match(/license\.txt/, error.message)
    assert_empty client.writes
  end

  should 'reconcile an upload that succeeded remotely before a timeout without duplicating it' do
    client = StatefulDspaceClient.new(bundles: [])
    original_upload = client.method(:upload_bitstream)
    interrupted = false
    client.define_singleton_method(:upload_bitstream) do |*args, **kwargs|
      result = original_upload.call(*args, **kwargs)
      unless interrupted
        interrupted = true
        raise Net::ReadTimeout, 'response lost'
      end
      result
    end
    service = ETD::EnsureLicenseBundle.new(client:, files: @files)
    uuid = SecureRandom.uuid
    assert_raises(Net::ReadTimeout) { service.call(item_uuid: uuid) }
    result = service.call(item_uuid: uuid)
    assert_equal :updated, result.status
    assert_equal ['YorkU_ETDlicense.txt'], result.uploaded_bitstreams.map { |file| file[:name] }
    assert_equal 3, client.writes.size
    assert_equal :complete, service.call(item_uuid: uuid).status
    assert_equal 3, client.writes.size
  end

  should 'preserve the verified generated licence and upload only the missing ETD licence' do
    files = ETD::LicenseFiles.canonical
    variant = files.first.fetch(:existing_variants).sole
    bundle_uuid = SecureRandom.uuid
    client = StatefulDspaceClient.new(bundles: [{
      'uuid' => bundle_uuid, 'name' => 'LICENSE', 'bitstreams' => [{
        'uuid' => SecureRandom.uuid, 'name' => 'license.txt', 'sizeBytes' => variant.fetch(:size),
        'checkSum' => { 'checkSumAlgorithm' => 'MD5', 'value' => variant.fetch(:md5) }
      }]
    }])
    service = ETD::EnsureLicenseBundle.new(client:)
    uuid = SecureRandom.uuid
    assert_equal ['YorkU_ETDlicense.txt'], service.call(item_uuid: uuid, dry_run: true).missing_files
    assert_equal :updated, service.call(item_uuid: uuid).status
    assert_equal 1, client.writes.size
    assert_equal 'YorkU_ETDlicense.txt', client.writes.first.fetch(:name)
    assert_equal :complete, service.call(item_uuid: uuid).status
    assert_equal 1, client.writes.size
  end

  private

  def write_license(name, contents)
    path = File.join(@directory, name)
    File.binwrite(path, contents)
    {
      name:,
      path:,
      size: contents.bytesize,
      md5: Digest::MD5.hexdigest(contents)
    }
  end
end
