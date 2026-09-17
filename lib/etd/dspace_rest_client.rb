# frozen_string_literal: true

require 'json'
require 'net/http'
require 'securerandom'
require 'uri'

module ETD
  class DspaceRestClient
    class RequestError < StandardError
      attr_reader :status

      def initialize(message, status: nil)
        @status = status
        super(message)
      end
    end

    def initialize(base_url:, username:, password:, transport: nil)
      @base_url = base_url.to_s.sub(%r{/+\z}, '')
      uri = URI.parse(@base_url)
      unless uri.scheme == 'https' && uri.host && !uri.userinfo && !uri.query && !uri.fragment
        raise ArgumentError, 'DSpace REST URL must be HTTPS without credentials, query or fragment'
      end
      @username = username
      @password = password
      @transport = transport || method(:perform_request)
      @authorization = nil
      @csrf_token = nil
      @csrf_cookie = nil
    end

    def create_bundle(item_uuid, name:)
      authenticate!
      response = request(
        :post,
        "/core/items/#{item_uuid}/bundles",
        body: JSON.generate(name:, metadata: {}),
        headers: { 'Content-Type' => 'application/json' },
        authenticated: true,
        csrf: true
      )
      parse_json(response)
    end

    def bundles(item_uuid)
      collection("/core/items/#{item_uuid}/bundles", 'bundles')
    end

    def bitstreams(bundle_uuid)
      collection("/core/bundles/#{bundle_uuid}/bitstreams", 'bitstreams')
    end

    def bitstream_content(bitstream_uuid)
      authenticate! if @username.present? && @password.present?
      request(:get, "/core/bitstreams/#{bitstream_uuid}/content",
              headers: { 'Accept' => 'application/octet-stream' },
              authenticated: @authorization.present?).body
    end

    def upload_bitstream(bundle_uuid, file_path:, name:)
      authenticate!
      body, boundary = multipart_body(file_path, name)
      response = request(
        :post,
        "/core/bundles/#{bundle_uuid}/bitstreams",
        body:,
        headers: {
          'Content-Type' => "multipart/form-data; boundary=#{boundary}",
          'Content-Length' => body.bytesize.to_s
        },
        authenticated: true,
        csrf: true
      )
      parse_json(response)
    end

    private

    def collection(path, key)
      authenticate! if @username.present? && @password.present?
      records = []
      page = 0
      loop do
        suffix = page.zero? ? '?size=100' : "?size=100&page=#{page}"
        response = request(:get, path + suffix, authenticated: @authorization.present?)
        data = parse_json(response)
        entries = data.dig('_embedded', key)
        entries = [] if entries.nil? && data.dig('page', 'totalElements') == 0
        raise RequestError, "Invalid DSpace #{key} collection" unless entries.is_a?(Array)

        records.concat(entries)
        total_pages = data.dig('page', 'totalPages')
        if total_pages.nil?
          raise RequestError, 'DSpace pagination is missing' if entries.size >= 100 || data.dig('_links', 'next')
          break
        end
        unless total_pages.is_a?(Integer) && total_pages.between?(0, 1000)
          raise RequestError, 'Invalid DSpace pagination'
        end
        page += 1
        break if page >= total_pages
      end
      records
    end

    def authenticate!
      return if @authorization.present?

      request(:get, '/security/csrf')
      if @csrf_token.blank? || @csrf_cookie.blank?
        raise RequestError, 'DSpace did not provide complete CSRF token and cookie state'
      end

      body = URI.encode_www_form(user: @username, password: @password)
      response = request(
        :post,
        '/authn/login',
        body:,
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
        csrf: true
      )
      @authorization = response['Authorization']
      raise RequestError, 'DSpace login response did not include an Authorization token' if @authorization.blank?
    end

    def request(method, path, body: nil, headers: {}, authenticated: false, csrf: false)
      uri = URI.parse("#{@base_url}#{path}")
      request = request_class(method).new(uri.request_uri)
      headers.each { |name, value| request[name] = value }
      request['Accept'] = headers.fetch('Accept', 'application/json')
      request['Authorization'] = @authorization if authenticated
      if csrf
        request['X-XSRF-TOKEN'] = @csrf_token
        request['Cookie'] = "DSPACE-XSRF-COOKIE=#{@csrf_cookie}" if @csrf_cookie
      end
      request.body = body if body

      response = @transport.call(uri, request)
      update_security_state(response)
      return response if response.code.to_i.between?(200, 299)

      raise RequestError.new("DSpace REST #{method.to_s.upcase} #{path} returned #{response.code}",
                             status: response.code.to_i)
    end

    def request_class(method)
      {
        get: Net::HTTP::Get,
        post: Net::HTTP::Post
      }.fetch(method)
    end

    def update_security_state(response)
      @csrf_token = response['DSPACE-XSRF-TOKEN'] if response['DSPACE-XSRF-TOKEN'].present?
      Array(response.get_fields('Set-Cookie')).each do |header|
        match = header.match(/(?:\A|;\s*)DSPACE-XSRF-COOKIE=([^;]+)/)
        @csrf_cookie = match[1] if match
      end
    end

    def parse_json(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      raise RequestError, 'DSpace REST returned invalid JSON'
    end

    def multipart_body(file_path, name)
      unless File.basename(name) == name && name.exclude?('"') && name.exclude?("\r") && name.exclude?("\n")
        raise ArgumentError, 'Bitstream name must be a plain filename'
      end

      boundary = "----etd-license-#{SecureRandom.hex(16)}"
      body = String.new(encoding: Encoding::BINARY)
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{name}\"\r\n"
      body << "Content-Type: text/plain\r\n\r\n"
      body << File.binread(file_path)
      body << "\r\n--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"properties\"\r\n"
      body << "Content-Type: application/json\r\n\r\n"
      body << JSON.generate(name:, metadata: {})
      body << "\r\n--#{boundary}--\r\n"
      [body, boundary]
    end

    def perform_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 15
      http.read_timeout = 120
      http.request(request)
    end
  end
end
