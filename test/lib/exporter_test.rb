# frozen_string_literal: true

require 'test_helper'
require 'etd/exporter'

class ExporterTest < ActiveSupport::TestCase
  class MediaEntryDouble
    attr_reader :media_posts

    def initialize
      @media_posts = []
    end

    def post_media!(**options)
      @media_posts << options
    end
  end

  class ReceiptDouble
    attr_reader :entry, :location, :status_code, :status_message

    def initialize(status_code: 201)
      @entry = MediaEntryDouble.new
      @location = 'https://example.test/item/1'
      @status_code = status_code
      @status_message = status_code == 201 ? 'Created' : 'Rejected'
    end
  end

  class CollectionDouble
    attr_reader :posts

    def initialize(receipt)
      @receipt = receipt
      @posts = []
    end

    def post!(**options)
      @posts << options
      @receipt
    end
  end

  class ConnectionDouble
    attr_reader :posts

    def initialize
      @posts = []
    end

    def post(*arguments)
      @posts << arguments
    end
  end

  should 'retain configured connection settings' do
    exporter = ETD::Exporter.new(username: 'user', password: 'secret',
                                 service_document_url: 'https://example.test/service',
                                 collection_uri: 'https://example.test/collection',
                                 collection_title: 'ETD')

    assert_equal 'user', exporter.username
    assert_equal 'secret', exporter.password
    assert_equal 'https://example.test/service', exporter.service_document_url
    assert_equal 'https://example.test/collection', exporter.collection_uri
    assert_equal 'ETD', exporter.collection_title
  end

  should 'return nil for an empty or invalid zip input' do
    exporter = ETD::Exporter.new

    assert_nil exporter.zip_files('/tmp/etd-empty-test.zip', [])
    assert_nil exporter.zip_files('/tmp/etd-invalid-test.zip', 'not an array')
  end

  should 'zip files and disambiguate duplicate archive names' do
    exporter = ETD::Exporter.new
    file = Rails.root.join('test/fixtures/files/pdf-document.pdf').to_s

    Dir.mktmpdir('etd-exporter-test') do |directory|
      archive = File.join(directory, 'documents.zip')
      assert_equal archive, exporter.zip_files(archive, [file, file])

      names = Zip::ZipFile.open(archive) { |zip| zip.entries.map(&:name) }
      assert_equal 2, names.size
      assert_equal 1, names.count { |name| name == File.basename(file) }
      assert names.any? { |name| name.end_with?(File.basename(file)) && name != File.basename(file) }
    end
  end

  should 'reject relative file paths before contacting the collection' do
    exporter = ETD::Exporter.new
    entry = Atom::Entry.new

    assert_raises RuntimeError do
      exporter.deposit(entry: entry, files: 'relative/document.pdf')
    end
  end

  should 'deposit media and send a completion signal for a successful receipt' do
    exporter = ETD::Exporter.new(username: 'exporter@example.com')
    receipt = ReceiptDouble.new(status_code: 201)
    collection = CollectionDouble.new(receipt)
    connection = ConnectionDouble.new
    exporter.instance_variable_set(:@collection, collection)
    exporter.instance_variable_set(:@connection, connection)
    entry = Atom::Entry.new
    file = Rails.root.join('test/fixtures/files/pdf-document.pdf').to_s

    result = exporter.deposit(entry: entry, files: file)

    assert_same receipt, result
    assert_equal [{ entry:, in_progress: true, on_behalf_of: 'exporter@example.com' }], collection.posts
    assert_equal [file], receipt.entry.media_posts.map { |post| post[:filepath] }
    assert_equal 'application/pdf', receipt.entry.media_posts.first[:content_type]
    assert_equal [[receipt.location, nil, { 'In-Progress' => 'false' }]], connection.posts
  end

  should 'not send media or completion when the collection rejects the entry' do
    exporter = ETD::Exporter.new
    receipt = ReceiptDouble.new(status_code: 400)
    collection = CollectionDouble.new(receipt)
    connection = ConnectionDouble.new
    exporter.instance_variable_set(:@collection, collection)
    exporter.instance_variable_set(:@connection, connection)
    file = Rails.root.join('test/fixtures/files/pdf-document.pdf').to_s

    exporter.deposit(entry: Atom::Entry.new, files: [file])

    assert_empty receipt.entry.media_posts
    assert_empty connection.posts
  end

  # should "connect to server or throw an error if can't" do
  #   exporter = ETD::Exporter.new
  #
  #   assert_nothing_raised do
  #     service = exporter.connect_to_server
  #     assert_not_nil service, "Service is prepared"
  #     assert_not_nil exporter.service, "Service property is exposed"
  #   end
  #
  #
  #   assert_raise RuntimeError do
  #     invalid_exporter = ETD::Exporter.new(username: "woowow")
  #     invalid_exporter.connect_to_server
  #   end
  # end
  #
  #
  # should "return a collection instance if found one, or raise RuntimeError otherise" do
  #   exporter = ETD::Exporter.new
  #
  #   assert_nothing_raised "Nothing should be raised" do
  #     collection = exporter.prepare_collection
  #     assert_not_nil collection, "Collection is not nill"
  #     assert_not_nil exporter.collection, "Collection has been set as a property"
  #   end
  #
  #   invalid_exporter = ETD::Exporter.new(collection_title: "Randomly selected")
  #   assert_raise RuntimeError do
  #     invalid_exporter.prepare_collection
  #   end
  # end
  #
  # should "zip a list of files and return the path to zipped file. The file should exist" do
  #   exporter = ETD::Exporter.new
  #
  #   files = [File.expand_path("test/fixtures/files/pdf-document.pdf"), File.expand_path("test/fixtures/files/pdf-document.pdf")]
  #
  #   zipped_file = exporter.zip_files("/tmp/etd-#{Time.now.to_i}.zip", files)
  #   assert_not_nil zipped_file, "It should return path to file"
  #   assert zipped_file.ends_with?("zip"), "It should be a zipped file"
  #   assert File.exist?(zipped_file), "File should exists"
  # end
  #
  #
  # should "return nil if Entry is not supplied to the deposit method or if entry is not Atom::Entry" do
  #   exporter = ETD::Exporter.new
  #   exporter.prepare_collection
  #
  #   assert_nil exporter.deposit, "Should return a nil "
  #   assert_nil exporter.deposit(entry: "Some String"), "Should return nil since entry must be of Atom::Entry"
  #   assert_not_nil exporter.deposit(entry: Atom::Entry.new), "Shouldn't return nil since proper Entry was supplied"
  # end
  #
  # should "deposit an entry and return a deposit receipt" do
  #   exporter = ETD::Exporter.new
  #   exporter.prepare_collection
  #
  #   entry = Atom::Entry.new
  #   entry.title = "From Exporter Test"
  #   entry.summary = "Something or other"
  #
  #   receipt = exporter.deposit(entry: entry, complete: true)
  #
  #   assert_not_nil receipt, "Should not be nil"
  #   assert receipt.instance_of?(Sword2Ruby::DepositReceipt), "Should be an instance Deposit Receipt"
  # end
  #
  # should "raise an error if file paths supplied are not absolute" do
  #   exporter = ETD::Exporter.new
  #   exporter.prepare_collection
  #
  #   entry = Atom::Entry.new
  #   entry.title = "From Exporter Test with files"
  #   entry.summary = "Something or other"
  #
  #   files = ["../../../test/fixtures/files/pdf-document.pdf", "../../../test/fixtures/files/pdf-document copy.Pdf"]
  #
  #   assert_raises RuntimeError do
  #     receipt = exporter.deposit(entry: entry, complete: true, files: files)
  #   end
  #
  # end
  #
  # should "depoist an entry and files and return a deposit receipt" do
  #   exporter = ETD::Exporter.new
  #   exporter.prepare_collection
  #
  #   entry = Atom::Entry.new
  #   entry.title = "From Exporter Test with files"
  #   entry.add_dublin_core_extension!("creator", "Some test author")
  #   entry.summary = "Something or other"
  #
  #   files = [File.expand_path("test/fixtures/files/pdf-document.pdf"),
  #     File.expand_path("test/fixtures/files/pdf-document.pdf")]
  #
  #   receipt = exporter.deposit(entry: entry, complete: true, files: files)
  #
  #   assert_not_nil receipt, "Should not be nil"
  #   assert receipt.instance_of?(Sword2Ruby::DepositReceipt), "Should be an instance Deposit Receipt"
  # end
  #
  # should "deposit an entry and zip the files before submission" do
  #
  #   exporter = ETD::Exporter.new
  #   exporter.prepare_collection
  #
  #   entry = Atom::Entry.new
  #   entry.title = "Zipped files"
  #   entry.summary = "Something or other"
  #
  #   files = [File.expand_path("test/fixtures/files/pdf-document.pdf"),
  #     File.expand_path("test/fixtures/files/pdf-document.pdf")]
  #
  #   receipt = exporter.deposit(entry: entry, complete: true, files: files, zipped: true)
  #
  #   assert_not_nil receipt, "Should not be nil"
  #   assert receipt.instance_of?(Sword2Ruby::DepositReceipt), "Should be an instance Deposit Receipt"
  #
  # end
end
