# frozen_string_literal: true

require 'etd/dspace_license_backfill'
require 'etd/dspace_rest_client'

namespace :dspace do
  namespace :licenses do
    desc 'Recover pending, interrupted and due failed licence jobs from the database'
    task recover: :environment do
      DspaceDeposit.where(license_status: [DspaceDeposit::PENDING, DspaceDeposit::RUNNING, DspaceDeposit::FAILED])
                   .where('license_retry_at IS NULL OR license_retry_at <= ?', Time.current).find_each do |deposit|
        begin
          DspaceLicenseBundleJob.perform_now(deposit.id)
        rescue StandardError => e
          warn "Licence recovery failed for deposit #{deposit.id}: #{e.class}"
        end
      end
    end

    desc 'Continuously recover durable licence work; run under a process supervisor'
    task worker: :environment do
      loop do
        Rake::Task['dspace:licenses:recover'].reenable
        Rake::Task['dspace:licenses:recover'].invoke
        sleep 60
      end
    end

    desc 'Dry-run or apply LICENSE bundles for DSpace item UUIDs in CSV column A'
    task backfill: :environment do
      csv_path = ENV.fetch('CSV_PATH')
      apply = ENV.fetch('APPLY', 'false').casecmp?('true')
      results_path = ENV['RESULTS_PATH'].presence
      base_url = ENV['DSPACE_REST_API_URL'].presence || AppSettings.dspace_rest_api_url
      username = ENV['DSPACE_REST_USERNAME'].presence || AppSettings.dspace_live_username
      password = ENV['DSPACE_REST_PASSWORD'].presence || AppSettings.dspace_live_password

      abort 'DSpace REST API URL is not configured' if base_url.blank?
      if apply
        abort 'Set CONFIRM=ATTACH_LICENSES to enable writes' unless ENV['CONFIRM'] == 'ATTACH_LICENSES'
        abort 'RESULTS_PATH is required when APPLY=true' if results_path.blank?
        abort 'DSpace REST username and password are required when APPLY=true' if username.blank? || password.blank?
      end

      output = results_path ? File.open(results_path, 'a') : $stdout
      client = ETD::DspaceRestClient.new(base_url:, username:, password:)
      summary = ETD::DspaceLicenseBackfill.new(client:, output:, apply:).run(
        csv_path:,
        item_uuid: ENV['ITEM_UUID'].presence,
        limit: ENV['LIMIT'].presence
      )
      $stdout.puts(JSON.generate(type: 'summary', apply:, **summary))
      abort 'Some records failed or require review; inspect the results file' if summary.fetch(:failed, 0).positive? || summary.fetch(:review_required, 0).positive?
    ensure
      output&.close if output && output != $stdout
    end
  end
end
