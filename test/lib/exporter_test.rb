require 'test_helper'
require 'etd/exporter'

class ExporterTest < ActiveSupport::TestCase
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
