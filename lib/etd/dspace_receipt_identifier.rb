# frozen_string_literal: true

require 'nokogiri'
require 'uri'

module ETD
  module DspaceReceiptIdentifier
    UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
    ITEM_PATH = %r{/(?:swordv2/(?:edit|edit-media)|api/core/items|items)/(?<uuid>#{UUID})(?:[/?#.]|\z)}i

    def self.item_uuid(receipt)
      sources = [receipt&.location]
      if receipt&.entry&.respond_to?(:to_xml)
        document = Nokogiri::XML(receipt.entry.to_xml.to_s) { |config| config.strict.nonet }
        sources.concat(document.xpath('//*[local-name()="link"]/@href | /*[local-name()="entry"]/*[local-name()="id"]').map(&:text))
      end

      identifiers = sources.compact.filter_map do |source|
        uri = URI.parse(source)
        next unless %w[https http].include?(uri.scheme) && uri.host

        uri.path.match(ITEM_PATH)&.named_captures&.fetch('uuid')&.downcase
      end.uniq
      identifiers.one? ? identifiers.first : nil
    rescue Nokogiri::XML::SyntaxError, URI::InvalidURIError
      nil
    end
  end
end
