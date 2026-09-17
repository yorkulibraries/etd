# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'json'
require 'etd/dspace_rest_client'
require 'etd/license_files'
require_relative '../support/sqlite_license_lock'

class DspaceLicenseCanaryTest < ActiveSupport::TestCase
  include SqliteLicenseLock

  class Client
    attr_reader :writes

    def initialize
      @bundle = nil
      @streams = []
      @writes = 0
    end

    def bundles(_uuid)
      @bundle ? [@bundle] : []
    end

    def bitstreams(_uuid)
      @streams
    end

    def create_bundle(_uuid, name:)
      @writes += 1
      @bundle = { 'uuid' => SecureRandom.uuid, 'name' => name }
    end

    def upload_bitstream(_uuid, file_path:, name:)
      @writes += 1
      @streams << { 'uuid' => SecureRandom.uuid, 'name' => name,
                    'sizeBytes' => File.size(file_path),
                    'checkSum' => { 'checkSumAlgorithm' => 'MD5', 'value' => Digest::MD5.file(file_path).hexdigest } }
      @streams.last
    end

    def bitstream_content(uuid)
      name = @streams.find { |stream| stream['uuid'] == uuid }.fetch('name')
      File.binread(ETD::LicenseFiles.canonical.find { |file| file[:name] == name }.fetch(:path))
    end
  end

  should 'validate one CSV member with two downloads and a no-op repeat' do
    Dir.mktmpdir('licence-canary') do |directory|
      csv = File.join(directory, 'items.csv')
      output = File.join(directory, 'report.jsonl')
      uuid = SecureRandom.uuid
      File.write(csv, "id\n#{uuid}\n")
      values = { 'CSV_PATH' => csv, 'RESULTS_PATH' => output, 'ITEM_UUID' => uuid,
                 'APPLY' => 'true', 'CONFIRM' => 'ATTACH_LICENSES',
                 'DSPACE_REST_API_URL' => 'https://repository.example/server/api',
                 'DSPACE_REST_USERNAME' => 'user', 'DSPACE_REST_PASSWORD' => 'secret' }
      previous = ENV.to_h.slice(*values.keys)
      ENV.update(values)
      client = Client.new
      ETD::DspaceRestClient.stubs(:new).returns(client)
      capture_io { load Rails.root.join('script/validate_dspace_license_canary.rb') }
      events = File.readlines(output).map { |line| JSON.parse(line) }
      assert_equal 3, client.writes
      assert_equal %w[before first_run repeat_run download_verified download_verified validated], events.map { |event| event['event'] }
      assert_equal 'complete', events[2]['status']
      assert_equal true, events.last['non_license_bundles_unchanged']
    ensure
      values&.each_key { |key| previous.key?(key) ? ENV[key] = previous[key] : ENV.delete(key) }
    end
  end
end
