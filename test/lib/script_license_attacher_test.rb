# frozen_string_literal: true

require 'test_helper'
require 'csv'
require 'stringio'
require 'tmpdir'
require 'etd/script_license_attacher'

# How the server deposit script's licence step can go wrong, written before the code:
# 1. A failed or missing SWORD receipt must not trigger any YorkSpace write.
# 2. An in-progress (not complete) deposit is not archived yet, so it must be skipped.
# 3. Turning the step off must skip it without touching YorkSpace.
# 4. A receipt without an item UUID must be reported with its thesis ID, not silently dropped.
# 5. A YorkSpace error (bad login, outage, busy lock) must never raise into the deposit loop.
# 6. Missing REST address or login must be reported per item, not crash the run.
# 7. Licences must go to the same server the thesis was deposited to.
# 8. Items that failed must end up in a retry file the backfill task can read directly.
# 9. A clean run must not leave a retry file behind.
class ScriptLicenseAttacherTest < ActiveSupport::TestCase
  UUID = '22222222-2222-4222-8222-222222222222'
  Receipt = Struct.new(:status_code, :location, :entry)

  setup do
    @log = StringIO.new
    @calls = []
    @dir = Dir.mktmpdir
  end

  teardown do
    FileUtils.remove_entry(@dir)
  end

  should 'attach licences after a successful complete deposit' do
    attacher = build_attacher

    assert_equal :attached, attacher.attach(receipt: good_receipt, thesis_id: 7)
    assert_equal [UUID], @calls
    assert_includes @log.string, "Licences attached for item #{UUID}"
  end

  should 'skip failed or missing receipts without calling YorkSpace' do
    attacher = build_attacher

    assert_equal :skipped, attacher.attach(receipt: Receipt.new(500, edit_url, nil), thesis_id: 7)
    assert_equal :skipped, attacher.attach(receipt: nil, thesis_id: 8)
    assert_empty @calls
    assert_empty attacher.failures
  end

  should 'skip in-progress deposits and runs where the step is turned off' do
    [build_attacher(complete: false), build_attacher(enabled: false)].each do |attacher|
      assert_equal :skipped, attacher.attach(receipt: good_receipt, thesis_id: 7)
    end
    assert_empty @calls
  end

  should 'report a receipt without an item UUID by thesis ID' do
    attacher = build_attacher

    assert_equal :failed, attacher.attach(receipt: Receipt.new(201, 'https://repo.example/elsewhere', nil), thesis_id: 42)
    assert_empty @calls
    assert_equal [42], attacher.failures.map(&:thesis_id)
    assert_nil attacher.failures.first.item_uuid
  end

  should 'never raise when YorkSpace rejects the licence step' do
    attacher = build_attacher(ensurer: ->(_uuid) { raise ETD::DspaceRestClient::RequestError.new('Unauthorized', status: 401) })

    assert_equal :failed, attacher.attach(receipt: good_receipt, thesis_id: 7)
    assert_equal [UUID], attacher.failures.map(&:item_uuid)
    assert_includes @log.string, 'LICENCE ERROR'
  end

  should 'report missing REST settings per item instead of crashing' do
    attacher = ETD::ScriptLicenseAttacher.from_env({ 'USERNAME' => 'u', 'PASSWORD' => 'p' }, complete: true, log: @log)

    assert_equal :failed, attacher.attach(receipt: good_receipt, thesis_id: 7)
    assert_match(/REST API URL/, attacher.failures.first.error)
  end

  should 'send licences to the server the thesis was deposited to' do
    settings = ETD::ScriptLicenseAttacher.rest_settings(
      'DSPACE' => 'https://ys.example/', 'USERNAME' => 'sword@example', 'PASSWORD' => 'secret'
    )
    assert_equal({ base_url: 'https://ys.example/server/api', username: 'sword@example', password: 'secret' }, settings)

    override = ETD::ScriptLicenseAttacher.rest_settings(
      'DSPACE' => 'https://ys.example', 'DSPACE_REST_API_URL' => 'https://other.example/server/api',
      'USERNAME' => 'sword@example', 'PASSWORD' => 'secret',
      'DSPACE_REST_USERNAME' => 'admin@example', 'DSPACE_REST_PASSWORD' => 'admin-secret'
    )
    assert_equal({ base_url: 'https://other.example/server/api', username: 'admin@example', password: 'admin-secret' }, override)
  end

  should 'write failed items to a retry file the backfill task can read' do
    attacher = build_attacher(ensurer: ->(_uuid) { raise 'timeout' })
    attacher.attach(receipt: good_receipt, thesis_id: 7)
    attacher.attach(receipt: Receipt.new(201, 'https://repo.example/elsewhere', nil), thesis_id: 9)
    path = File.join(@dir, 'retry.csv')

    attacher.finish(retry_path: path)

    rows = CSV.read(path, headers: true)
    assert_equal [UUID], rows.map { |row| row[0] }
    assert_includes @log.string, 'dspace:licenses:backfill'
    assert_includes @log.string, 'Thesis 9'
  end

  should 'not leave a retry file after a clean run' do
    attacher = build_attacher
    attacher.attach(receipt: good_receipt, thesis_id: 7)
    path = File.join(@dir, 'retry.csv')

    attacher.finish(retry_path: path)

    refute File.exist?(path)
    assert_includes @log.string, 'Licences attached: 1. Licence failures: 0.'
  end

  private

  def build_attacher(enabled: true, complete: true, ensurer: nil)
    ensurer ||= ->(uuid) { @calls << uuid }
    ETD::ScriptLicenseAttacher.new(enabled:, complete:, log: @log, ensurer:)
  end

  def edit_url
    "https://repo.example/server/swordv2/edit/#{UUID}"
  end

  def good_receipt
    Receipt.new(201, edit_url, nil)
  end
end
