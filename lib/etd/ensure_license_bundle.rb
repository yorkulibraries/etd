# frozen_string_literal: true

require 'digest'
require 'etd/license_files'
require 'etd/license_item_lock'

module ETD
  class EnsureLicenseBundle
    class ConflictError < StandardError; end
    class PayloadError < StandardError; end

    Result = Struct.new(:status, :missing_files, :bundle_uuid, :uploaded_bitstreams, keyword_init: true)

    def initialize(client:, files: LicenseFiles.canonical)
      @client = client
      @files = files
    end

    def call(item_uuid:, dry_run: false)
      return ensure_bundle(item_uuid:, dry_run:) if dry_run

      LicenseItemLock.synchronize(item_uuid) { ensure_bundle(item_uuid:, dry_run:) }
    end

    private

    def ensure_bundle(item_uuid:, dry_run:)
      validate_payloads!
      license_bundles = @client.bundles(item_uuid).select { |bundle| bundle.fetch('name') == 'LICENSE' }
      raise ConflictError, 'Multiple LICENSE bundles require manual review' if license_bundles.many?

      bundle = license_bundles.first
      bitstreams = bundle ? @client.bitstreams(bundle.fetch('uuid')) : []
      missing_files = missing_file_names(bitstreams)

      if bundle && missing_files.empty?
        return Result.new(
          status: :complete,
          missing_files: [],
          bundle_uuid: bundle.fetch('uuid'),
          uploaded_bitstreams: []
        )
      end

      if dry_run
        return Result.new(
          status: :dry_run,
          missing_files:,
          bundle_uuid: bundle&.fetch('uuid'),
          uploaded_bitstreams: []
        )
      end

      unless bundle
        @client.create_bundle(item_uuid, name: 'LICENSE')
        license_bundles = @client.bundles(item_uuid).select { |candidate| candidate.fetch('name') == 'LICENSE' }
        raise ConflictError, 'LICENSE bundle could not be identified after creation' unless license_bundles.one?

        bundle = license_bundles.first
        bitstreams = @client.bitstreams(bundle.fetch('uuid'))
        missing_files = missing_file_names(bitstreams)
      end

      uploaded_bitstreams = missing_files.map do |name|
        file = @files.find { |candidate| candidate.fetch(:name) == name }
        bitstream = @client.upload_bitstream(bundle.fetch('uuid'), file_path: file.fetch(:path), name:)
        bitstreams = @client.bitstreams(bundle.fetch('uuid'))
        unless missing_file_names(bitstreams).exclude?(name)
          raise ConflictError, "Uploaded LICENSE bitstream could not be verified: #{name}"
        end
        { name:, uuid: bitstream.fetch('uuid') }
      end

      remaining_files = missing_file_names(@client.bitstreams(bundle.fetch('uuid')))
      raise ConflictError, "LICENSE bundle remains incomplete: #{remaining_files.join(', ')}" if remaining_files.any?

      Result.new(
        status: :updated,
        missing_files: [],
        bundle_uuid: bundle.fetch('uuid'),
        uploaded_bitstreams:
      )
    end

    private

    def validate_payloads!
      @files.each do |file|
        path = file.fetch(:path)
        valid = File.file?(path) &&
                File.size(path) == file.fetch(:size) &&
                Digest::MD5.file(path).hexdigest.casecmp?(file.fetch(:md5))
        if valid && file.key?(:sha256)
          valid = Digest::SHA256.file(path).hexdigest.casecmp?(file.fetch(:sha256))
        end
        raise PayloadError, "Local licence payload failed verification: #{file.fetch(:name)}" unless valid
      end
    end

    def missing_file_names(bitstreams)
      expected_names = @files.map { |file| file.fetch(:name) }
      unexpected_names = bitstreams.map { |bitstream| bitstream.fetch('name') }.reject do |name|
        expected_names.include?(name)
      end
      if unexpected_names.any?
        raise ConflictError, "Unexpected LICENSE bitstreams: #{unexpected_names.uniq.join(', ')}"
      end

      @files.filter_map do |file|
        matches = bitstreams.select { |bitstream| bitstream.fetch('name') == file.fetch(:name) }
        if matches.many?
          raise ConflictError, "Duplicate LICENSE bitstream: #{file.fetch(:name)}"
        end
        next file.fetch(:name) if matches.empty?

        unless matching_bitstream?(matches.first, file)
          raise ConflictError, "LICENSE bitstream differs from canonical file: #{file.fetch(:name)}"
        end
      end
    end

    def matching_bitstream?(bitstream, file)
      checksum = bitstream.fetch('checkSum')
      [file, *file.fetch(:existing_variants, [])].any? do |version|
        bitstream.fetch('sizeBytes') == version.fetch(:size) &&
          checksum.fetch('checkSumAlgorithm').casecmp?('MD5') &&
          checksum.fetch('value').casecmp?(version.fetch(:md5))
      end
    end
  end
end
