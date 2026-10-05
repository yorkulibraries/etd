# frozen_string_literal: true

require 'test_helper'
require 'etd/dspace_etd_community'

class DspaceEtdCommunityTest < ActiveSupport::TestCase
  PRODUCTION_UUID = '9eb3679d-898f-4180-9335-bd3211dd87fb'

  should 'accept the known production community' do
    client = HandleClient.new(
      base_url: 'https://yorkspace.library.yorku.ca/server/api',
      community: community(PRODUCTION_UUID)
    )

    resolved = ETD::DspaceEtdCommunity.resolve(client)

    assert_equal PRODUCTION_UUID, resolved.fetch(:uuid)
    assert_equal '10315/26310', resolved.fetch(:handle)
    assert_equal ['10315/26310'], client.handles
  end

  should 'refuse a different community uuid on production YorkSpace' do
    client = HandleClient.new(
      base_url: 'https://yorkspace.library.yorku.ca/server/api',
      community: community('11111111-1111-4111-8111-111111111111')
    )

    error = assert_raises(ETD::DspaceEtdCommunity::Error) { ETD::DspaceEtdCommunity.resolve(client) }

    assert_match(/UUID/, error.message)
  end

  should 'accept another uuid when the REST host is not production' do
    uuid = '11111111-1111-4111-8111-111111111111'
    client = HandleClient.new(
      base_url: 'https://ys.library.yorku.ca/server/api',
      community: community(uuid)
    )

    assert_equal uuid, ETD::DspaceEtdCommunity.resolve(client).fetch(:uuid)
  end

  should 'refuse a handle that does not resolve to the ETD community' do
    client = HandleClient.new(
      base_url: 'https://ys.library.yorku.ca/server/api',
      community: community(PRODUCTION_UUID).merge('type' => 'collection')
    )

    assert_raises(ETD::DspaceEtdCommunity::Error) { ETD::DspaceEtdCommunity.resolve(client) }
  end

  class HandleClient
    attr_reader :handles, :base_url

    def initialize(base_url:, community:)
      @base_url = base_url
      @community = community
      @handles = []
    end

    def find_handle(handle)
      @handles << handle
      @community
    end
  end

  def community(uuid)
    { 'uuid' => uuid, 'handle' => '10315/26310', 'type' => 'community' }
  end
end
