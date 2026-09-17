# frozen_string_literal: true

require 'csv'
require 'json'
require 'etd/dspace_receipt_identifier'
require 'etd/ensure_license_bundle'

module ETD
  class DspaceLicenseBackfill
    class InputError < StandardError; end

    UUID_FORMAT = /\A#{DspaceReceiptIdentifier::UUID}\z/i

    def initialize(client:, output:, apply: false)
      @client = client
      @output = output
      @apply = apply
    end

    def run(csv_path:, item_uuid: nil, limit: nil)
      item_uuids = read_item_uuids(csv_path)
      if item_uuid.present?
        raise InputError, "Canary item UUID is not present in column A: #{item_uuid}" unless item_uuids.include?(item_uuid)

        item_uuids = [item_uuid]
      end
      if limit.present?
        raise InputError, 'LIMIT must be a positive integer' unless limit.to_s.match?(/\A[1-9][0-9]*\z/)

        item_uuids = item_uuids.first(limit.to_i)
      end

      summary = { total: item_uuids.size }
      item_uuids.each do |uuid|
        result = EnsureLicenseBundle.new(client: @client).call(item_uuid: uuid, dry_run: !@apply)
        status = result.status.to_s
        summary[status.to_sym] = summary.fetch(status.to_sym, 0) + 1
        write_record(
          item_uuid: uuid,
          status:,
          bundle_uuid: result.bundle_uuid,
          missing_files: result.missing_files,
          uploaded_bitstreams: result.uploaded_bitstreams
        )
      rescue EnsureLicenseBundle::ConflictError, EnsureLicenseBundle::PayloadError => e
        summary[:review_required] = summary.fetch(:review_required, 0) + 1
        write_record(item_uuid: uuid, status: 'review_required', error: e.message)
      rescue StandardError => e
        summary[:failed] = summary.fetch(:failed, 0) + 1
        write_record(item_uuid: uuid, status: 'failed', error: e.message)
      end
      summary
    end

    private

    def read_item_uuids(csv_path)
      raise InputError, "CSV file does not exist: #{csv_path}" unless File.file?(csv_path)

      item_uuids = CSV.foreach(csv_path, headers: true).map { |row| row[0].to_s.strip }
      invalid = item_uuids.reject { |uuid| uuid.match?(UUID_FORMAT) }
      raise InputError, "Invalid item UUIDs in column A: #{invalid.uniq.join(', ')}" if invalid.any?

      duplicates = item_uuids.tally.select { |_uuid, count| count > 1 }.keys
      raise InputError, "Duplicate item UUIDs in column A: #{duplicates.join(', ')}" if duplicates.any?

      item_uuids
    end

    def write_record(record)
      @output.puts(JSON.generate(record.compact))
      @output.flush if @output.respond_to?(:flush)
    end
  end
end
