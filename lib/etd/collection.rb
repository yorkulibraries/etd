# frozen_string_literal: true

require 'base64'
require 'atom/element'
require 'atom/collection'
require 'unicode'

module Sword2Ruby
  # Extensions to the atom-tools[https://github.com/bct/atom-tools/wiki] Atom::Collection class to support Sword2 operations.
  # These methods are additive to those supplied by the atom-tools gem.
  #
  # Please see the {atom-tools documentation}[http://rdoc.info/github/bct/atom-tools/master/frames] for a complete list of attributes and methods.
  module ::Atom
    class Collection < ::Atom::Element
      def post!(params = {})
        Utility.check_argument_class('params', params, Hash)
        defaults = {
          entry: nil,
          slug: nil,
          collection_uri:,
          in_progress: nil,
          on_behalf_of: nil,
          connection: @http
        }
        options = defaults.merge(params)

        # Validate parameters
        Utility.check_argument_class(':entry', options[:entry], ::Atom::Entry)
        Utility.check_argument_class(':slug', options[:slug], String) if options[:slug]
        Utility.check_argument_class(':collection_uri', options[:collection_uri], String)
        Utility.check_argument_class(':on_behalf_of', options[:on_behalf_of], String) if options[:on_behalf_of]
        Utility.check_argument_class(':connection', options[:connection], Sword2Ruby::Connection)

        headers = { 'Content-Type' => 'application/atom+xml;type=entry' }
        headers['Slug'] = options[:slug] if options[:slug]
        if options[:in_progress] == true || options[:in_progress] == false
          headers['In-Progress'] =
            options[:in_progress].to_s.downcase
        end
        headers['On-Behalf-Of'] = options[:on_behalf_of] if options[:on_behalf_of]

        response = options[:connection].post(options[:collection_uri], options[:entry].to_s, headers)

        if response.is_a? Net::HTTPSuccess
          DepositReceipt.new(response, options[:connection])
        else
          raise Sword2Ruby::Exception,
                "Failed to do post!(#{options[:collection_uri]}): server returned code #{response.code} #{response.message}"
        end
      end
    end
  end
end
