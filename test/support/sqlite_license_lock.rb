# frozen_string_literal: true

require 'minitest/mock'
require 'etd/license_item_lock'

# SQLite has no named locks. Isolate only that boundary in behaviour tests;
# the same tests and the dedicated concurrency integration use real MySQL locks.
module SqliteLicenseLock
  def run(*args, &block)
    return super unless ActiveRecord::Base.connection.adapter_name == 'SQLite'

    lock = ->(_item_uuid, &operation) { operation.call }
    ETD::LicenseItemLock.stub(:synchronize, lock) { super }
  end
end
