# frozen_string_literal: true

require 'json'
require 'etd/dspace_etd_community'
require 'etd/dspace_rest_client'

module ETD
  class DspaceMissingLicenses
    PROGRESS_INTERVAL = 100
    SETTLED = %w[missing has_license_bundle].freeze

    def initialize(client:, missing_path:, results_path:, progress: $stderr)
      @client = client
      @missing_path = missing_path
      @results_path = results_path
      @progress = progress
      @community = nil
      @latest = {}
      @order = []
      @seen = {}
      @loaded = false
      @results = nil
      @total_expected = nil
      @checked = 0
      @fatal_error = nil
    end

    def run
      @community = DspaceEtdCommunity.resolve(@client)
      load_latest
      @loaded = true
      @results = File.open(@results_path, 'a')
      @client.search_item_uuids(@community.fetch(:uuid)) do |page|
        @total_expected = page.fetch(:total_elements)
        page.fetch(:uuids).each { |uuid| consider(uuid) }
      end
      summary
    rescue DspaceEtdCommunity::Error
      raise
    rescue StandardError => e
      @fatal_error = e.message
      summary
    ensure
      @results&.close
      safe_rewrite
    end

    private

    def load_latest
      return unless File.file?(@results_path)

      File.foreach(@results_path) do |line|
        next if line.strip.empty?

        data = JSON.parse(line)
        uuid = data['item_uuid'].to_s.downcase
        next if uuid.empty? || data['command'] != 'missing'

        @order << uuid unless @order.include?(uuid)
        @latest[uuid] = data['status']
      end
    end

    def consider(uuid)
      uuid = uuid.to_s.downcase
      return if @seen[uuid]

      @seen[uuid] = true
      unless SETTLED.include?(@latest[uuid])
        attributes = classify(uuid)
        write_record({ command: 'missing', item_uuid: uuid }.merge(attributes))
        @latest[uuid] = attributes.fetch(:status)
        @order << uuid unless @order.include?(uuid)
      end
      @checked += 1
      @progress.puts("checked #{@checked} items") if (@checked % PROGRESS_INTERVAL).zero?
    end

    def classify(uuid)
      bundles = @client.with_transient_retry { @client.bundles(uuid) }
      count = bundles.count { |bundle| bundle.fetch('name') == 'LICENSE' }
      {
        status: count.zero? ? 'missing' : 'has_license_bundle',
        license_bundle_count: count
      }
    rescue DspaceRestClient::RequestError => e
      status = [401, 403].include?(e.status) ? 'unreadable' : 'failed'
      { status:, error: e.message }
    end

    def write_record(record)
      @results.puts(JSON.generate(record))
      @results.flush
    end

    def summary
      counts = Hash.new(0)
      @latest.each_value { |status| counts[status] += 1 }
      complete = @fatal_error.nil? && !@total_expected.nil? && @latest.size == @total_expected &&
                 @latest.each_value.all? { |status| SETTLED.include?(status) }
      result = {
        community_uuid: @community&.fetch(:uuid),
        authenticated: @client.credentials?,
        total_expected: @total_expected,
        missing: counts['missing'],
        has_license_bundle: counts['has_license_bundle'],
        unreadable: counts['unreadable'],
        failed: counts['failed'],
        complete:
      }
      result[:error] = @fatal_error if @fatal_error
      result
    end

    def safe_rewrite
      return unless @loaded

      rewrite_missing_ids
    rescue StandardError => e
      @progress.puts("Could not rewrite missing ID file: #{e.class}")
    end

    def rewrite_missing_ids
      lines = @order.select { |uuid| @latest[uuid] == 'missing' }
      body = lines.empty? ? '' : "#{lines.join("\n")}\n"
      temporary = File.join(File.dirname(@missing_path), ".#{File.basename(@missing_path)}.#{Process.pid}.tmp")
      File.write(temporary, body)
      File.rename(temporary, @missing_path)
    ensure
      File.delete(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
    end
  end
end
