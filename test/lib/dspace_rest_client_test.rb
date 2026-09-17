# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'tempfile'
require 'etd/dspace_rest_client'

class DspaceRestClientTest < ActiveSupport::TestCase
  class Response
    attr_reader :code, :body

    def initialize(code:, body: '', headers: {})
      @code = code.to_s
      @body = body
      @headers = headers.transform_keys(&:downcase)
    end

    def [](name)
      value = @headers[name.downcase]
      value.is_a?(Array) ? value.first : value
    end

    def get_fields(name)
      Array(@headers[name.downcase]).presence
    end
  end

  class RecordingTransport
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def call(uri, request)
      @requests << [uri, request]
      @responses.shift || raise('Unexpected HTTP request')
    end
  end

  should 'authenticate with DSpace CSRF state before creating a bundle' do
    transport = RecordingTransport.new([
      Response.new(
        code: 200,
        headers: {
          'DSPACE-XSRF-TOKEN' => 'csrf-one',
          'Set-Cookie' => 'DSPACE-XSRF-COOKIE=cookie-one; Path=/; Secure'
        }
      ),
      Response.new(
        code: 200,
        headers: {
          'Authorization' => 'Bearer jwt-value',
          'DSPACE-XSRF-TOKEN' => 'csrf-two',
          'Set-Cookie' => 'DSPACE-XSRF-COOKIE=cookie-two; Path=/; Secure'
        }
      ),
      Response.new(
        code: 201,
        body: JSON.generate('uuid' => '11111111-1111-4111-8111-111111111111', 'name' => 'LICENSE')
      )
    ])
    client = ETD::DspaceRestClient.new(
      base_url: 'https://repository.example/server/api',
      username: 'depositor@example.org',
      password: 'secret password',
      transport:
    )

    bundle = client.create_bundle('22222222-2222-4222-8222-222222222222', name: 'LICENSE')

    assert_equal '11111111-1111-4111-8111-111111111111', bundle.fetch('uuid')
    assert_equal [
      ['GET', '/server/api/security/csrf'],
      ['POST', '/server/api/authn/login'],
      ['POST', '/server/api/core/items/22222222-2222-4222-8222-222222222222/bundles']
    ], transport.requests.map { |uri, request| [request.method, uri.path] }

    login_request = transport.requests.fetch(1).last
    assert_equal 'csrf-one', login_request['X-XSRF-TOKEN']
    assert_equal 'DSPACE-XSRF-COOKIE=cookie-one', login_request['Cookie']
    assert_equal 'application/x-www-form-urlencoded', login_request['Content-Type']
    assert_equal 'user=depositor%40example.org&password=secret+password', login_request.body

    create_request = transport.requests.fetch(2).last
    assert_equal 'Bearer jwt-value', create_request['Authorization']
    assert_equal 'csrf-two', create_request['X-XSRF-TOKEN']
    assert_equal 'DSPACE-XSRF-COOKIE=cookie-two', create_request['Cookie']
    assert_equal({ 'name' => 'LICENSE', 'metadata' => {} }, JSON.parse(create_request.body))
  end

  should 'refuse a write when DSpace does not provide complete CSRF state' do
    transport = RecordingTransport.new([Response.new(code: 200, headers: { 'DSPACE-XSRF-TOKEN' => 'csrf-only' })])
    client = ETD::DspaceRestClient.new(
      base_url: 'https://repository.example/server/api',
      username: 'depositor@example.org',
      password: 'secret password',
      transport:
    )

    error = assert_raises(ETD::DspaceRestClient::RequestError) do
      client.create_bundle('22222222-2222-4222-8222-222222222222', name: 'LICENSE')
    end

    assert_match(/CSRF/, error.message)
    assert_equal 1, transport.requests.size
  end

  should 'read an item bundle collection without authenticating' do
    expected_bundle = { 'uuid' => '11111111-1111-4111-8111-111111111111', 'name' => 'LICENSE' }
    transport = RecordingTransport.new([
      Response.new(
        code: 200,
        body: JSON.generate('_embedded' => { 'bundles' => [expected_bundle] })
      )
    ])
    client = ETD::DspaceRestClient.new(
      base_url: 'https://repository.example/server/api',
      username: nil,
      password: nil,
      transport:
    )

    bundles = client.bundles('22222222-2222-4222-8222-222222222222')

    assert_equal [expected_bundle], bundles
    uri, request = transport.requests.first
    assert_equal 'GET', request.method
    assert_equal '/server/api/core/items/22222222-2222-4222-8222-222222222222/bundles', uri.path
    assert_equal 'size=100', uri.query
    assert_nil request['Authorization']
  end

  should 'read a bundle bitstream collection without authenticating' do
    expected_bitstream = {
      'uuid' => '33333333-3333-4333-8333-333333333333',
      'name' => 'license.txt',
      'sizeBytes' => 1913,
      'checkSum' => { 'checkSumAlgorithm' => 'MD5', 'value' => 'ad94d0cd27da622da832da123b629d9c' }
    }
    transport = RecordingTransport.new([
      Response.new(
        code: 200,
        body: JSON.generate('_embedded' => { 'bitstreams' => [expected_bitstream] })
      )
    ])
    client = ETD::DspaceRestClient.new(
      base_url: 'https://repository.example/server/api',
      username: nil,
      password: nil,
      transport:
    )

    bitstreams = client.bitstreams('11111111-1111-4111-8111-111111111111')

    assert_equal [expected_bitstream], bitstreams
    uri, request = transport.requests.first
    assert_equal 'GET', request.method
    assert_equal '/server/api/core/bundles/11111111-1111-4111-8111-111111111111/bitstreams', uri.path
    assert_equal 'size=100', uri.query
  end

  should 'upload one bitstream as authenticated multipart form data' do
    file = Tempfile.new(['license', '.txt'])
    file.binmode
    file.write("approved licence bytes\r\n")
    file.close
    expected_bitstream = {
      'uuid' => '33333333-3333-4333-8333-333333333333',
      'name' => 'license.txt',
      'sizeBytes' => 24,
      'checkSum' => { 'checkSumAlgorithm' => 'MD5', 'value' => 'placeholder' }
    }
    transport = RecordingTransport.new([
      Response.new(
        code: 200,
        headers: {
          'DSPACE-XSRF-TOKEN' => 'csrf-one',
          'Set-Cookie' => 'DSPACE-XSRF-COOKIE=cookie-one; Path=/'
        }
      ),
      Response.new(code: 200, headers: { 'Authorization' => 'Bearer jwt-value' }),
      Response.new(code: 201, body: JSON.generate(expected_bitstream))
    ])
    client = ETD::DspaceRestClient.new(
      base_url: 'https://repository.example/server/api',
      username: 'depositor@example.org',
      password: 'secret password',
      transport:
    )

    bitstream = client.upload_bitstream(
      '11111111-1111-4111-8111-111111111111',
      file_path: file.path,
      name: 'license.txt'
    )

    assert_equal expected_bitstream, bitstream
    uri, request = transport.requests.fetch(2)
    assert_equal 'POST', request.method
    assert_equal '/server/api/core/bundles/11111111-1111-4111-8111-111111111111/bitstreams', uri.path
    assert_match(%r{\Amultipart/form-data; boundary=}, request['Content-Type'])
    assert_includes request.body, "approved licence bytes\r\n"
    assert_includes request.body, 'name="file"; filename="license.txt"'
    assert_includes request.body, 'name="properties"'
    assert_includes request.body, '"name":"license.txt"'
  ensure
    file&.close!
  end

  should 'authenticate reads and include every page before deciding what exists' do
    transport = RecordingTransport.new([
      Response.new(code: 200, headers: {
        'DSPACE-XSRF-TOKEN' => 'csrf', 'Set-Cookie' => 'DSPACE-XSRF-COOKIE=cookie; Path=/'
      }),
      Response.new(code: 200, headers: { 'Authorization' => 'Bearer token' }),
      Response.new(code: 200, body: JSON.generate('_embedded' => { 'bundles' => [{ 'name' => 'ORIGINAL' }] },
                                                'page' => { 'totalPages' => 2 })),
      Response.new(code: 200, body: JSON.generate('_embedded' => { 'bundles' => [{ 'name' => 'LICENSE' }] },
                                                'page' => { 'totalPages' => 2 }))
    ])
    client = ETD::DspaceRestClient.new(base_url: 'https://repository.example/server/api',
                                     username: 'user', password: 'secret', transport:)
    assert_equal %w[ORIGINAL LICENSE], client.bundles(SecureRandom.uuid).map { |bundle| bundle['name'] }
    assert_equal ['Bearer token', 'Bearer token'], transport.requests.last(2).map { |_, request| request['Authorization'] }
    assert_equal 'size=100&page=1', transport.requests.last.first.query
  end

  should 'reject malformed collections instead of treating them as empty' do
    transport = RecordingTransport.new([Response.new(code: 200, body: '{}')])
    client = ETD::DspaceRestClient.new(base_url: 'https://repository.example/server/api',
                                     username: nil, password: nil, transport:)
    assert_raises(ETD::DspaceRestClient::RequestError) { client.bundles(SecureRandom.uuid) }
  end

  should 'accept an explicitly empty paged collection' do
    transport = RecordingTransport.new([Response.new(code: 200, body: '{"page":{"totalElements":0,"totalPages":0}}')])
    client = ETD::DspaceRestClient.new(base_url: 'https://repository.example/server/api',
                                     username: nil, password: nil, transport:)
    assert_empty client.bundles(SecureRandom.uuid)
  end

  should 'reject HTTP before sending credentials and keep server error bodies out of logs' do
    assert_raises(ArgumentError) do
      ETD::DspaceRestClient.new(base_url: 'http://repository.example', username: 'user', password: 'secret')
    end
    transport = RecordingTransport.new([Response.new(code: 500, body: 'secret-token')])
    client = ETD::DspaceRestClient.new(base_url: 'https://repository.example/server/api',
                                     username: nil, password: nil, transport:)
    error = assert_raises(ETD::DspaceRestClient::RequestError) { client.bundles(SecureRandom.uuid) }
    assert_equal 500, error.status
    refute_includes error.message, 'secret-token'
  end
end
