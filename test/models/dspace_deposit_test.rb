# frozen_string_literal: true

require 'test_helper'

class DspaceDepositTest < ActiveSupport::TestCase
  should 'record one pending licence operation for a deposited thesis item' do
    deposit = DspaceDeposit.new(
      thesis: create(:thesis),
      export_log: create(:export_log),
      item_uuid: '22222222-2222-4222-8222-222222222222',
      sword_location: 'https://repository.example/server/swordv2/edit/22222222-2222-4222-8222-222222222222'
    )

    assert deposit.valid?
    assert_equal DspaceDeposit::PENDING, deposit.license_status
  end

  should 'reject an invalid DSpace item UUID' do
    deposit = DspaceDeposit.new(
      thesis: create(:thesis),
      export_log: create(:export_log),
      item_uuid: 'not-an-item-uuid'
    )

    assert_not deposit.valid?
    assert_includes deposit.errors[:item_uuid], 'is not a UUID'
  end
end
