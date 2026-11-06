# frozen_string_literal: true

require 'csv'
require 'etd/dspace_receipt_identifier'
require 'etd/dspace_rest_client'
require 'etd/ensure_license_bundle'

module ETD
  # Attaches the LICENSE bundle right after each deposit made by the server
  # deposit script (rake dspace:export). A licence problem never fails the
  # thesis deposit; failed items are collected into a backfill retry file.
  class ScriptLicenseAttacher
    Failure = Struct.new(:thesis_id, :item_uuid, :error, keyword_init: true)

    attr_reader :failures

    def self.rest_settings(env)
      deposit_server = env['DSPACE'].to_s.strip.chomp('/')
      {
        base_url: env['DSPACE_REST_API_URL'].presence || (deposit_server.present? ? "#{deposit_server}/server/api" : nil),
        username: env['DSPACE_REST_USERNAME'].presence || env['USERNAME'].presence,
        password: env['DSPACE_REST_PASSWORD'].presence || env['PASSWORD'].presence
      }
    end

    def self.from_env(env, complete:, log:)
      settings = rest_settings(env)
      client = nil
      ensurer = lambda do |item_uuid|
        raise 'DSpace REST API URL is not configured' if settings[:base_url].blank?
        raise 'DSpace REST username and password are not configured' if settings[:username].blank? || settings[:password].blank?

        client ||= DspaceRestClient.new(**settings)
        EnsureLicenseBundle.new(client:).call(item_uuid:)
      end
      new(enabled: !env['ATTACH_LICENCES'].to_s.casecmp?('false'), complete:, log:, ensurer:,
          rest_url: settings[:base_url])
    end

    def initialize(enabled:, complete:, log:, ensurer:, rest_url: nil)
      @enabled = enabled && complete
      @log = log
      @ensurer = ensurer
      @rest_url = rest_url
      @attached = 0
      @failures = []
    end

    def enabled?
      @enabled
    end

    def attach(receipt:, thesis_id:)
      return :skipped unless @enabled
      return :skipped unless receipt&.status_code.to_i.between?(200, 299)

      item_uuid = DspaceReceiptIdentifier.item_uuid(receipt)
      return record_failure(thesis_id, nil, 'SWORD receipt did not include a DSpace item UUID') unless item_uuid

      @ensurer.call(item_uuid)
      @attached += 1
      @log.puts "Licences attached for item #{item_uuid}"
      :attached
    rescue StandardError => e
      record_failure(thesis_id, item_uuid, "#{e.class}: #{e.message}")
    end

    def finish(retry_path:)
      return unless @enabled

      @log.puts "\nLicences attached: #{@attached}. Licence failures: #{@failures.size}."
      return if @failures.empty?

      @failures.reject(&:item_uuid).each do |failure|
        @log.puts "  Thesis #{failure.thesis_id}: #{failure.error} (find the item in YorkSpace and add it to a backfill CSV)"
      end

      retryable = @failures.select(&:item_uuid)
      return if retryable.empty?

      CSV.open(retry_path, 'w') do |csv|
        csv << %w[item_uuid thesis_id error]
        retryable.each { |failure| csv << [failure.item_uuid, failure.thesis_id, failure.error] }
      end
      @log.puts "  #{retryable.size} item(s) saved to #{retry_path}. Retry with the same login as this deposit:"
      @log.puts "  RAILS_ENV=production CSV_PATH=#{retry_path} #{"DSPACE_REST_API_URL=#{@rest_url} " if @rest_url}" \
                'DSPACE_REST_USERNAME=... DSPACE_REST_PASSWORD=... APPLY=true CONFIRM=ATTACH_LICENSES ' \
                "RESULTS_PATH=#{retry_path.to_s.sub(/\.csv\z/, '')}.results.jsonl bundle exec rake dspace:licenses:backfill"
    end

    private

    def record_failure(thesis_id, item_uuid, error)
      @failures << Failure.new(thesis_id:, item_uuid:, error:)
      @log.puts "LICENCE ERROR for thesis #{thesis_id}#{" (item #{item_uuid})" if item_uuid}: #{error}"
      :failed
    end
  end
end
