# frozen_string_literal: true

require 'digest'

module ETD
  module LicenseItemLock
    class Busy < StandardError; end

    def self.synchronize(item_uuid)
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        name = connection.quote("etd-license-#{Digest::SHA256.hexdigest(item_uuid.downcase)[0, 48]}")
        acquired = connection.select_value("SELECT GET_LOCK(#{name}, 0)").to_i == 1
        raise Busy, 'Another licence operation is running for this item' unless acquired

        begin
          yield
        ensure
          connection.select_value("SELECT RELEASE_LOCK(#{name})")
        end
      end
    end
  end
end
