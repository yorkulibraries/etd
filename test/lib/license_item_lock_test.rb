# frozen_string_literal: true

require 'test_helper'
require 'etd/license_item_lock'

class LicenseItemLockTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  should 'exclude a second database connection and release after exceptions' do
    uuid = SecureRandom.uuid
    ETD::LicenseItemLock.synchronize(uuid) do
      thread = Thread.new do
        assert_raises(ETD::LicenseItemLock::Busy) { ETD::LicenseItemLock.synchronize(uuid) { flunk 'Concurrent writer entered' } }
      end
      thread.value
      ETD::LicenseItemLock.synchronize(uuid) { assert true }
    end
    assert_raises(RuntimeError) { ETD::LicenseItemLock.synchronize(uuid) { raise 'interrupted' } }
    Thread.new { ETD::LicenseItemLock.synchronize(uuid) { assert true } }.value
  end
end
