# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'stringio'
require 'tempfile'
require 'etd/dspace_license_backfill'

class DspaceLicenseBackfillTest < ActiveSupport::TestCase
  should 'reject invalid limits rather than accidentally applying the full CSV' do
    csv = Tempfile.new(['etd-items', '.csv'])
    csv.write("id,title\n22222222-2222-4222-8222-222222222222,Example thesis\n")
    csv.close
    client = ReadOnlyClient.new
    ['0', '-1', 'one', '1oops'].each do |limit|
      assert_raises(ETD::DspaceLicenseBackfill::InputError) do
        ETD::DspaceLicenseBackfill.new(client:, output: StringIO.new, apply: true).run(csv_path: csv.path, limit:)
      end
    end
    assert_empty client.writes
  ensure
    csv&.close!
  end

  class ReadOnlyClient
    attr_reader :writes

    def initialize
      @writes = []
    end

    def bundles(_item_uuid)
      []
    end
  end

  should 'read item UUIDs from column A and report a dry run without writes' do
    csv = Tempfile.new(['etd-items', '.csv'])
    csv.write("id,title\n22222222-2222-4222-8222-222222222222,Example thesis\n")
    csv.close
    output = StringIO.new
    client = ReadOnlyClient.new

    summary = ETD::DspaceLicenseBackfill.new(client:, output:, apply: false).run(csv_path: csv.path)

    assert_equal({ total: 1, dry_run: 1 }, summary)
    record = JSON.parse(output.string)
    assert_equal '22222222-2222-4222-8222-222222222222', record.fetch('item_uuid')
    assert_equal 'dry_run', record.fetch('status')
    assert_equal ['license.txt', 'YorkU_ETDlicense.txt'], record.fetch('missing_files')
    assert_empty client.writes
  ensure
    csv&.close!
  end

  should 'reject a canary UUID that is not present in the CSV' do
    csv = Tempfile.new(['etd-items', '.csv'])
    csv.write("id,title\n22222222-2222-4222-8222-222222222222,Example thesis\n")
    csv.close
    client = ReadOnlyClient.new

    error = assert_raises(ETD::DspaceLicenseBackfill::InputError) do
      ETD::DspaceLicenseBackfill.new(client:, output: StringIO.new, apply: false).run(
        csv_path: csv.path,
        item_uuid: '33333333-3333-4333-8333-333333333333'
      )
    end

    assert_match(/not present/, error.message)
    assert_empty client.writes
  ensure
    csv&.close!
  end
end
