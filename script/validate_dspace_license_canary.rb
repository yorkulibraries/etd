# Run with bundle exec rails runner script/validate_dspace_license_canary.rb
require 'csv'
require 'digest'
require 'json'
require 'etd/dspace_rest_client'
require 'etd/dspace_receipt_identifier'
require 'etd/ensure_license_bundle'

uuid = ENV.fetch('ITEM_UUID')
abort 'ITEM_UUID must be a UUID' unless uuid.match?(/\A#{ETD::DspaceReceiptIdentifier::UUID}\z/i)
rows = CSV.read(ENV.fetch('CSV_PATH'), headers: true)
abort 'ITEM_UUID must occur exactly once in CSV column A' unless rows.count { |row| row[0].to_s.strip == uuid } == 1
apply = ENV.fetch('APPLY', 'false').casecmp?('true')
abort 'Set CONFIRM=ATTACH_LICENSES to enable writes' if apply && ENV['CONFIRM'] != 'ATTACH_LICENSES'
username = ENV['DSPACE_REST_USERNAME'].presence || AppSettings.dspace_live_username
password = ENV['DSPACE_REST_PASSWORD'].presence || AppSettings.dspace_live_password
abort 'Configure DSpace credentials before applying the canary' if apply && (username.blank? || password.blank?)
client = ETD::DspaceRestClient.new(
  base_url: ENV['DSPACE_REST_API_URL'].presence || AppSettings.dspace_rest_api_url,
  username:, password:
)

snapshot = lambda do
  client.bundles(uuid).reject { |bundle| bundle.fetch('name') == 'LICENSE' }.map do |bundle|
    files = client.bitstreams(bundle.fetch('uuid')).map do |file|
      file.slice('uuid', 'name', 'sizeBytes', 'checkSum')
    end.sort_by { |file| file.fetch('uuid') }
    { uuid: bundle.fetch('uuid'), name: bundle.fetch('name'), files: }
  end.sort_by { |bundle| bundle.fetch(:uuid) }
end

File.open(ENV.fetch('RESULTS_PATH'), 'a', 0o600) do |output|
  emit = lambda do |event, details|
    output.puts(JSON.generate(time: Time.current.iso8601, item_uuid: uuid, event:, **details))
    output.flush
    output.fsync
  end
  begin
    ETD::LicenseItemLock.synchronize(uuid) do
      before = snapshot.call
      emit.call('before', apply:, csv_sha256: Digest::SHA256.file(ENV.fetch('CSV_PATH')).hexdigest, bundles: before)
      service = ETD::EnsureLicenseBundle.new(client:)
      result = service.call(item_uuid: uuid, dry_run: !apply)
      emit.call('first_run', result.to_h)
      if apply
        repeat = service.call(item_uuid: uuid)
        raise 'Repeat run was not a no-op' unless repeat.status == :complete && repeat.uploaded_bitstreams.empty?

        emit.call('repeat_run', repeat.to_h)
        streams = client.bitstreams(repeat.bundle_uuid)
        ETD::LicenseFiles.canonical.each do |file|
          stream = streams.find { |candidate| candidate.fetch('name') == file.fetch(:name) }
          bytes = client.bitstream_content(stream.fetch('uuid'))
          sha256 = Digest::SHA256.hexdigest(bytes)
          accepted_hashes = [file, *file.fetch(:existing_variants, [])].map { |version| version.fetch(:sha256) }
          raise "Downloaded bytes differ: #{file.fetch(:name)}" unless accepted_hashes.include?(sha256)

          emit.call('download_verified', name: file.fetch(:name), uuid: stream.fetch('uuid'), sha256:)
        end
        after = snapshot.call
        raise 'Non-LICENSE bundles changed during validation; inspect before rollout' unless before == after

        emit.call('validated', non_license_bundles_unchanged: true)
      end
    end
  rescue StandardError => e
    emit.call('failed', error_class: e.class.name, error: e.message)
    raise
  end
end
puts apply ? 'Canary validated; inspect its full record page before rollout.' : 'Read-only canary check complete; no files attached.'
