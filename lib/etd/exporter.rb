require "rubygems"
require "sword2ruby"
require 'ostruct'
require "zip/zip"

require_relative "http"
require_relative "atom_http_response"
require_relative "deposit_receipt"

module ETD

  class Exporter
    attr_reader :username, :password, :service_document_url, :collection_uri, :collection_title
    attr_reader :collection, :service

    # Create a new instance of Exporter and tell it where to deposit Theses to
    # Options:
    # username: The user name to use
    # password: The password for the user
    # service_document_url: The url of service document that describes SWORD service
    # collection_uri: Which collection to deposit into
    # collection_title: The title of the collection, used to ensure we're publishing to the right collection
    def initialize(params = {})
      defaults = {
        username: "user@email.com", password: "blah blah blah",
        service_document_url: "https://yourdspaceurl.com/swordv2/servicedocument",
        collection_uri: "https://yourdspaceurl/swordv2/collection/12345/6789",
        collection_title: "Some Collection"
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
        raise RuntimeError.new "Can't Connect To the Service. #{e.message}"
      end

    end

    # Find and prepare a collection we're going to be depositing into. The name and uri of collection is used to match a collection
    # IMPORTANT: This method invokes self.connect_to_server method
    # Returns collection or raises "Collection not found" exception
    def prepare_collection
      self.connect_to_server
        #puts "#{@service.collections.size} "
      @service.collections.find do |c|

        if (c.title.to_s == @collection_title && c.href.to_s == @collection_uri)
          return @collection = c
        end
      end

      raise RuntimeError.new("Collection not found in this instance")
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

      return nil if options.entry == nil || !options.entry.instance_of?(Atom::Entry)

      # ensure files is an array
      options.files = [] if options.files == nil
      options.files = [options.files] if options.files.instance_of?(String)
      raise "Files parameter has to be a String or an Array of strings" if !options.files.instance_of?(Array)

      options.files.each do |file_path|
        raise "File paths must be absolute, #{file_path}. #{options.entry.title} was not deposited." if !file_path.starts_with?("/")
      end

      # try and deposit

      # 1) Deposit Entry, by default always keep submission in progress, it will be completed in step 3 if required
      deposit_receipt = @collection.post!(entry: options.entry, in_progress: true, on_behalf_of: options.on_behalf_of)


      # 2) Deposit Media if any (zip first if required)
      if options.files.size > 0 && deposit_receipt.status_code.to_i >= 200
        if options.zipped
          @zipped_file = zip_files("/tmp/etd-#{Time.now.to_i}.zip", options.files)
          e = deposit_receipt.entry
          deposit_receipt.entry.post_media!(filepath: @zipped_file , content_type: "application/zip", packaging: "http://purl.org/net/sword/package/SimpleZip")
        else
          # if there are files to send and original entry has been successfully deposited
          options.files.each do |file_path|
            e = deposit_receipt.entry
            deposit_receipt.entry.post_media!(filepath: file_path , content_type: get_content_type(file_path))
          end
        end
      end

      # 3) Send a completed signal if required
      if options.complete && deposit_receipt.status_code.to_i >= 200
        # send a completion flag
        deposit_receipt.entry.put!(in_progress: false)
      end

      # 4) Delete the tmp file if it exits      
      if @zipped_file != nil && File.exist?(@zipped_file)
        puts "DELETING #{@zipped_file}"
        #File.delete(@zipped_file)
      end

      return deposit_receipt
    end


    # Get the content type of the file by reading it
    def get_content_type(file_path)
      return IO.popen(["file", "--brief", "--mime-type", file_path], in: :close, err: :close).read.chomp
    end

    # Zips files
    # zipped_file_path: where to place the zipped file and what to call it. Default: /tmp/etd-{timestamp}.zip
    # files: a list of files to be zipped. Array. Absolute Paths have to be used
    # Returns the path to the zipped file
    def zip_files(zipped_file_path = "/tmp/etd-#{Time.now.to_i}.zip", files = [])
      return nil if !files.instance_of?(Array) || files.size == 0

      zipped_files = []

      Zip::ZipFile.open(zipped_file_path, Zip::ZipFile::CREATE) do |zipfile|
        files.each do |filepath|
          filename = File.basename(filepath)

          # ensure there are no duplicate files
          if zipped_files.include?(filename)
            filename = "#{Time.now.to_i}-" + filename
          end

          zipped_files.push(filename)

          # Two arguments:
          # - The name of the file as it will appear in the archive
          # - The original file, including the path to find it
          zipfile.add(filename, filepath)
        end
      end

      return zipped_file_path
    end
  end
end
