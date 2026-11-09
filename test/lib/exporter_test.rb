# frozen_string_literal: true

require 'test_helper'
require Rails.root.join('lib/etd/exporter.rb')

# How one YorkSpace deposit can go wrong, written before the code:
# 1. A file is missing or is 2GB or more: the item is made without it and nobody is told.
#    -> refuse before anything is sent (NothingSent).
# 2. YorkSpace refuses the new item with an error code. Its error type is not a normal Ruby error,
#    so it skipped the per-thesis handling and stopped the whole export. -> NothingSent.
# 3. YorkSpace cannot be reached at all. -> NothingSent.
# 4. A timeout while the item is being created: it may or may not exist. -> passed on unchanged,
#    so the caller treats it as "needs checking".
# 6. A gateway error (502, 503 or 504) on item creation can arrive after YorkSpace made the item.
#    Treating it as "nothing sent" would resend the thesis as a second item. -> UncertainDeposit.
# 5. A file upload or the "finish" step fails after the item exists: the result was ignored and the
#    thesis counted as done, or the thesis was later resent as a second item. -> PartialDeposit.
class ExporterTest < ActiveSupport::TestCase
  Receipt = Struct.new(:status_code, :location, :entry)

  class FakeEntry
    attr_reader :uploads

    def initialize(fail_upload: nil)
      @fail_upload = fail_upload
      @uploads = []
    end

    def post_media!(filepath:, content_type:)
      raise @fail_upload if @fail_upload

      @uploads << [filepath, content_type]
    end
  end

  class FakeCollection
    attr_reader :posts

    def initialize(receipt: nil, error: nil)
      @receipt = receipt
      @error = error
      @posts = 0
    end

    def post!(**_arguments)
      @posts += 1
      raise @error if @error

      @receipt
    end
  end

  class FakeConnection
    attr_reader :requests

    def initialize(response)
      @response = response
      @requests = []
    end

    def post(url, body, headers)
      @requests << [url, body, headers]
      @response
    end
  end

  setup do
    @file = Rails.root.join('test/fixtures/files/pdf-document.pdf').to_s
    @entry = Atom::Entry.new
  end

  should 'refuse a missing file before sending anything to YorkSpace' do
    exporter, collection, = build_exporter

    error = assert_raises(ETD::Exporter::NothingSent) do
      exporter.deposit(entry: @entry, files: ['/no/such/thesis.pdf'])
    end

    assert_includes error.message, 'thesis.pdf'
    assert_equal 0, collection.posts
  end

  should 'refuse a file of 2GB or more before sending anything to YorkSpace' do
    exporter, collection, = build_exporter
    File.stubs(:size).with(@file).returns(ETD::Exporter::TWO_GIGABYTES)

    assert_raises(ETD::Exporter::NothingSent) { exporter.deposit(entry: @entry, files: [@file]) }
    assert_equal 0, collection.posts
  end

  should 'report a refused new item as nothing sent, as a normal error' do
    exporter, = build_exporter(error: Sword2Ruby::Exception.new('Failed to do post!: server returned code 500'))

    error = assert_raises(ETD::Exporter::NothingSent) { exporter.deposit(entry: @entry, files: [@file]) }

    assert_kind_of StandardError, error
    assert_includes error.message, '500'
  end

  should 'report a gateway error on item creation as uncertain, because the item may exist' do
    %w[502 503 504].each do |code|
      exporter, = build_exporter(error: Sword2Ruby::Exception.new("Failed to do post!(x): server returned code #{code} Bad Gateway"))

      error = assert_raises(ETD::Exporter::UncertainDeposit) { exporter.deposit(entry: @entry, files: [@file]) }
      assert_includes error.message, code
    end
  end

  should 'report an unreachable YorkSpace as nothing sent' do
    exporter, = build_exporter(error: Errno::ECONNREFUSED.new)

    assert_raises(ETD::Exporter::NothingSent) { exporter.deposit(entry: @entry, files: [@file]) }
  end

  should 'pass on a timeout while the item is being created, because it may exist' do
    exporter, = build_exporter(error: Net::ReadTimeout.new)

    assert_raises(Net::ReadTimeout) { exporter.deposit(entry: @entry, files: [@file]) }
  end

  should 'report a failed file upload after the item exists as a partial deposit' do
    receipt = Receipt.new(201, 'https://ys.example/swordv2/edit/1',
                          FakeEntry.new(fail_upload: Sword2Ruby::Exception.new('server returned 500')))
    exporter, = build_exporter(receipt:)

    error = assert_raises(ETD::Exporter::PartialDeposit) { exporter.deposit(entry: @entry, files: [@file]) }

    assert_equal receipt, error.receipt
    assert_includes error.message, '500'
  end

  should 'report a refused finish step as a partial deposit' do
    receipt = Receipt.new(201, 'https://ys.example/swordv2/edit/1', FakeEntry.new)
    exporter, = build_exporter(receipt:, response: Net::HTTPInternalServerError.new('1.1', '500', 'Error'))

    error = assert_raises(ETD::Exporter::PartialDeposit) { exporter.deposit(entry: @entry, files: [@file]) }

    assert_includes error.message, '500'
  end

  should 'upload every file and finish the submission when YorkSpace accepts it' do
    entry = FakeEntry.new
    receipt = Receipt.new(201, 'https://ys.example/swordv2/edit/1', entry)
    exporter, _collection, connection = build_exporter(receipt:)

    assert_equal receipt, exporter.deposit(entry: @entry, files: [@file], complete: true)
    assert_equal [@file], entry.uploads.map(&:first)
    assert_equal [['https://ys.example/swordv2/edit/1', nil, { 'In-Progress' => 'false' }]], connection.requests
  end

  private

  def build_exporter(receipt: nil, error: nil, response: Net::HTTPOK.new('1.1', '200', 'OK'))
    exporter = ETD::Exporter.new
    collection = FakeCollection.new(receipt:, error:)
    connection = FakeConnection.new(response)
    exporter.instance_variable_set(:@collection, collection)
    exporter.instance_variable_set(:@connection, connection)
    [exporter, collection, connection]
  end
end
