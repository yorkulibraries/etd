# frozen_string_literal: true

require 'test_helper'
require 'etd/dspace_receipt_identifier'

class DspaceReceiptIdentifierTest < ActiveSupport::TestCase
  should 'extract UUIDs from actual Atom links with quoted attributes' do
    require 'atom/entry'
    uuid = '22222222-2222-4222-8222-222222222222'
    entry = Atom::Entry.parse(%(<entry xmlns="http://www.w3.org/2005/Atom"><id>https://repository.example/items/#{uuid}</id><link rel="edit" href="https://repository.example/server/swordv2/edit/#{uuid}"/></entry>))
    receipt = Struct.new(:location, :entry).new(nil, entry)
    assert_equal uuid, ETD::DspaceReceiptIdentifier.item_uuid(receipt)
  end

  should 'reject conflicting item links and ignore URLs in descriptive text' do
    uuid = '22222222-2222-4222-8222-222222222222'
    other = '33333333-3333-4333-8333-333333333333'
    entry = mock
    entry.stubs(:to_xml).returns(%(<entry><link href="https://repository.example/items/#{uuid}"/><link href="https://repository.example/items/#{other}"/></entry>))
    assert_nil ETD::DspaceReceiptIdentifier.item_uuid(Struct.new(:location, :entry).new(nil, entry))
    entry.stubs(:to_xml).returns(%(<entry><title>https://repository.example/items/#{other}</title></entry>))
    assert_equal uuid, ETD::DspaceReceiptIdentifier.item_uuid(Struct.new(:location, :entry).new("https://repository.example/items/#{uuid}", entry))
  end

  should 'extract the DSpace item UUID from a SWORD edit location' do
    receipt = Struct.new(:location, :entry).new(
      'https://repository.example/server/swordv2/edit/22222222-2222-4222-8222-222222222222',
      nil
    )

    assert_equal '22222222-2222-4222-8222-222222222222',
                 ETD::DspaceReceiptIdentifier.item_uuid(receipt)
  end

  should 'ignore unrelated UUIDs in an unrecognized receipt URL' do
    receipt = Struct.new(:location, :entry).new(
      'https://repository.example/server/workspaces/33333333-3333-4333-8333-333333333333',
      nil
    )

    assert_nil ETD::DspaceReceiptIdentifier.item_uuid(receipt)
  end
end
