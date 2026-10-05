# frozen_string_literal: true

require 'json'
require 'etd/dspace_etd_community'
require 'etd/dspace_receipt_identifier'
require 'etd/dspace_rest_client'
require 'etd/ensure_license_bundle'
require 'etd/license_item_lock'

module ETD
  class DspaceLicenseAttach
    class InputError < StandardError; end

    UUID_FORMAT = /\A#{DspaceReceiptIdentifier::UUID}\z/i
    FAILURES = %i[out_of_scope unreadable review_required failed].freeze
    STATUSES = %w[dry_run complete updated out_of_scope review_required unreadable failed].freeze

    def self.validate_invocation!(apply:, confirm:, results_path:, username:, password:, adapter_name:)
      return unless apply

      raise InputError, 'Set CONFIRM=ATTACH_LICENSES to enable writes' unless confirm == 'ATTACH_LICENSES'
      raise InputError, 'RESULTS_PATH is required when APPLY=true' if results_path.nil? || results_path.to_s.empty?
      if username.nil? || username.to_s.empty? || password.nil? || password.to_s.empty?
        raise InputError, 'DSpace REST username and password are required when APPLY=true'
      end
      return if adapter_name.to_s.match?(/mysql/i)

      raise InputError, 'Licence attachment requires MySQL'
    end

    def self.successful?(summary)
      FAILURES.none? { |status| summary.fetch(status, 0).to_i.positive? }
    end

    def initialize(client:, output:, apply: false, bundle_factory: nil)
      @client = client
      @output = output
      @apply = apply
      @bundle_factory = bundle_factory || ->(rest_client) { EnsureLicenseBundle.new(client: rest_client) }
    end

    def run(ids_path:)
      ids = read_ids(ids_path)
      community = DspaceEtdCommunity.resolve(@client)
      collections = @client.community_collection_uuids(community.fetch(:uuid))
      counts = Hash.new(0)
      ids.each do |item_uuid|
        counts[process_item(item_uuid, collections)] += 1
      end
      summary_for(community.fetch(:uuid), ids.size, counts)
    end

    private

    def read_ids(path)
      raise InputError, "ID file does not exist: #{path}" unless File.file?(path)

      ids = []
      File.readlines(path, chomp: true).each_with_index do |line, index|
        next if line.strip.empty?

        raise InputError, "Invalid item UUID on line #{index + 1}" unless line.match?(UUID_FORMAT)

        ids << line.downcase
      end
      duplicates = ids.tally.select { |_uuid, count| count > 1 }.keys
      raise InputError, "Duplicate item UUIDs: #{duplicates.join(', ')}" if duplicates.any?

      ids
    end

    def process_item(item_uuid, collections)
      owning = @client.owning_collection_uuid(item_uuid)
      mapped = @client.mapped_collection_uuids(item_uuid)
      unless collections.include?(owning) || mapped.any? { |uuid| collections.include?(uuid) }
        write_record(command: 'attach', item_uuid:, status: 'out_of_scope', error: 'Item is outside the ETD community')
        return 'out_of_scope'
      end

      result = @bundle_factory.call(@client).call(item_uuid:, dry_run: !@apply)
      record = {
        command: 'attach',
        item_uuid:,
        status: result.status.to_s,
        bundle_uuid: result.bundle_uuid
      }
      record[:missing_files] = result.missing_files if result.status == :dry_run
      record[:uploaded_bitstreams] = result.uploaded_bitstreams if result.status == :updated
      write_record(record)
      result.status.to_s
    rescue EnsureLicenseBundle::PayloadError
      raise
    rescue EnsureLicenseBundle::ConflictError => e
      write_record(command: 'attach', item_uuid:, status: 'review_required', error: e.message)
      'review_required'
    rescue LicenseItemLock::Busy => e
      write_record(command: 'attach', item_uuid:, status: 'failed', error: e.message)
      'failed'
    rescue DspaceRestClient::RequestError => e
      status = [401, 403].include?(e.status) ? 'unreadable' : 'failed'
      write_record(command: 'attach', item_uuid:, status:, error: e.message)
      status
    end

    def write_record(record)
      @output.puts(JSON.generate(record.compact))
      @output.flush if @output.respond_to?(:flush)
    end

    def summary_for(community_uuid, total, counts)
      summary = { community_uuid:, apply: @apply, total: }
      STATUSES.each { |status| summary[status.to_sym] = counts[status] }
      summary
    end
  end
end
