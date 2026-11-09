# frozen_string_literal: true

require 'rubygems'
require 'sword2ruby'
require 'ostruct'
require 'zip/zip'

require_relative 'http'
require_relative 'atom_http_response'
require_relative 'deposit_receipt'

module ETD
  class Exporter
    attr_reader :username, :password, :service_document_url, :collection_uri, :collection_title, :collection, :service

    TWO_GIGABYTES = 2 * 1024**3

    # Nothing was kept in YorkSpace, so the thesis can safely be sent again later.
    class NothingSent < StandardError; end

    # YorkSpace made the item, but a later step failed. Sending again would make a second item.
    class PartialDeposit < StandardError
      attr_reader :receipt

      def initialize(message, receipt = nil)
        super(message)
        @receipt = receipt
      end
    end

    # YorkSpace may or may not have made the item (for example a gateway error after it was made).
    class UncertainDeposit < StandardError; end

    # Gateway errors can come from a proxy after YorkSpace already made the item.
    UNCERTAIN_STATUS_CODES = %w[502 503 504].freeze

    # Errors that mean the request never reached YorkSpace.
    NOT_CONNECTED_ERRORS = [Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError,
                            Net::OpenTimeout].freeze

    # Create a new instance of Exporter and tell it where to deposit Theses to
    # Options:
    # username: The user name to use
    # password: The password for the user
    # service_document_url: The url of service document that describes SWORD service
    # collection_uri: Which collection to deposit into
    # collection_title: The title of the collection, used to ensure we're publishing to the right collection
    def initialize(params = {})
      defaults = {
        username: 'user@email.com', password: 'blah blah blah',
        service_document_url: 'https://yourdspaceurl.com/swordv2/servicedocument',
        collection_uri: 'https://yourdspaceurl/swordv2/collection/12345/6789',
        collection_title: 'Some Collection'
      }

      options = OpenStruct.new(defaults.merge(params))

      @username = options.username
      @password = options.password
      @service_document_url = options.service_document_url
      @collection_uri = options.collection_uri
      @collection_title = options.collection_title
    end

    # Connect to server using the credentials
    # It will raise an Error if there it can't connect to the server or authenticate or can't accept content type
    def connect_to_server
      user_credentials = Sword2Ruby::User.new(@username, @password)

      # Define the connection object using the username and password
      @connection = Sword2Ruby::Connection.new(user_credentials)

      # Get the Service Document
      begin
        @service = Atom::Service.new(@service_document_url, @connection)
      rescue Exception => e
        raise "Can't Connect To the Service. #{e.message}"
      end
    end

    # Find and prepare a collection we're going to be depositing into. The name and uri of collection is used to match a collection
    # IMPORTANT: This method invokes self.connect_to_server method
    # Returns collection or raises "Collection not found" exception
    def prepare_collection
      connect_to_server
      # puts "#{@service.collections.size} "
      @service.collections.find do |c|
        return @collection = c if c.title.to_s == @collection_title && c.href.to_s == @collection_uri
      end

      raise 'Collection not found in this instance'
    end

    # Deposit Atom Entry and Files
    # entry: Atom Entry to deposit (Required)
    # files: An array or a single file to deposit. Filepaths must be ABSOLUTE (Default: empty)
    # zipped: Should the file(s) be zipped (Default: false)
    # on_behalf_of: On whose behalf is this being done (Default: Exporter.username)
    # complete: Should the deposit be completed at the end (Default: true)
    def deposit(params = {})
      defaults = { entry: nil, files: [], zipped: false, on_behalf_of: @username, complete: true }
      options = OpenStruct.new(defaults.merge(params))

      return nil if options.entry.nil? || !options.entry.instance_of?(Atom::Entry)

      # ensure files is an array
      options.files = [] if options.files.nil?
      options.files = [options.files] if options.files.instance_of?(String)
      raise 'Files parameter has to be a String or an Array of strings' unless options.files.instance_of?(Array)

      options.files.each { |file_path| check_file!(file_path, options.entry) }

      # 1) Deposit Entry, kept in progress until the files are added (step 3 completes it if required).
      #    sword2ruby raises its own error type for an error status; it is not a StandardError.
      begin
        deposit_receipt = @collection.post!(entry: options.entry, in_progress: true,
                                            on_behalf_of: options.on_behalf_of)
      rescue Sword2Ruby::Exception => e
        code = e.message[/server returned (?:code )?(\d{3})/, 1]
        raise UncertainDeposit, "YorkSpace may have made the item: #{e.message}" if UNCERTAIN_STATUS_CODES.include?(code)

        raise NothingSent, "YorkSpace did not accept the new item: #{e.message}"
      rescue *NOT_CONNECTED_ERRORS => e
        raise NothingSent, "YorkSpace could not be reached: #{e.message}"
      end

      # From here YorkSpace has the item, so any failure is a partial deposit.
      begin
        # 2) Deposit each file
        options.files.each do |file_path|
          deposit_receipt.entry.post_media!(filepath: file_path, content_type: get_content_type(file_path))
        end

        # 3) Send a completed signal if required
        if options.complete
          response = @connection.post(deposit_receipt.location, nil, { 'In-Progress' => 'false' })
          unless response.is_a?(Net::HTTPSuccess)
            raise "YorkSpace did not finish the submission: server returned #{response&.code} #{response&.message}"
          end
        end
      rescue StandardError, Sword2Ruby::Exception => e
        raise PartialDeposit.new("YorkSpace made the item but a later step failed: #{e.message}", deposit_receipt)
      end

      deposit_receipt
    end

    # Refuse before anything is sent: a missing or oversized file would leave the item without it.
    def check_file!(file_path, entry)
      raise NothingSent, "File paths must be absolute, #{file_path}. #{entry.title} was not deposited." unless file_path.start_with?('/')
      raise NothingSent, "File not found: #{File.basename(file_path)}. Nothing was sent." unless File.file?(file_path)
      return if File.size(file_path) < TWO_GIGABYTES

      raise NothingSent, "File is 2GB or more, too large for YorkSpace: #{File.basename(file_path)}. Nothing was sent."
    end

    # Get the content type of the file by reading it
    def get_content_type(file_path)
      IO.popen(['file', '--brief', '--mime-type', file_path], in: :close, err: :close).read.chomp
    end

    # Zips files
    # zipped_file_path: where to place the zipped file and what to call it. Default: /tmp/etd-{timestamp}.zip
    # files: a list of files to be zipped. Array. Absolute Paths have to be used
    # Returns the path to the zipped file
    def zip_files(zipped_file_path = "/tmp/etd-#{Time.now.to_i}.zip", files = [])
      return nil if !files.instance_of?(Array) || files.empty?

      zipped_files = []

      Zip::ZipFile.open(zipped_file_path, Zip::ZipFile::CREATE) do |zipfile|
        files.each do |filepath|
          filename = File.basename(filepath)

          # ensure there are no duplicate files
          filename = "#{Time.now.to_i}-" + filename if zipped_files.include?(filename)

          zipped_files.push(filename)

          # Two arguments:
          # - The name of the file as it will appear in the archive
          # - The original file, including the path to find it
          zipfile.add(filename, filepath)
        end
      end

      zipped_file_path
    end
  end
end
