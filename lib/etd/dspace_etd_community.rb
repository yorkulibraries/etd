# frozen_string_literal: true

require 'uri'

module ETD
  class DspaceEtdCommunity
    HANDLE = '10315/26310'
    PRODUCTION_HOST = 'yorkspace.library.yorku.ca'
    PRODUCTION_UUID = '9eb3679d-898f-4180-9335-bd3211dd87fb'

    class Error < StandardError; end

    def self.resolve(client)
      community = client.find_handle(HANDLE)
      uuid = community['uuid'].to_s.downcase
      handle = community['handle'].to_s
      type = community['type'].to_s
      unless type == 'community' && handle == HANDLE && !uuid.empty?
        raise Error, 'DSpace handle 10315/26310 did not resolve to the ETD community'
      end

      host = URI.parse(client.base_url).host
      if host == PRODUCTION_HOST && uuid != PRODUCTION_UUID
        raise Error, 'Production YorkSpace ETD community UUID did not match'
      end

      { uuid:, handle:, host: }
    end
  end
end
