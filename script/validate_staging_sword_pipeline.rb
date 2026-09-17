# Run locally with Rails runner. Default is a local-only rehearsal, with DB rollback.
require 'json'
require 'digest'
require 'tempfile'
require 'securerandom'
require 'net/http'
require Rails.root.join('lib/etd/exporter')
require Rails.root.join('lib/etd/ensure_license_bundle')

abort 'This harness requires Rails development, never production' unless Rails.env.development?
apply = ENV['APPLY'] == 'true'
abort 'Set CONFIRM=STAGING_SWORD_TEST' if apply && ENV['CONFIRM'] != 'STAGING_SWORD_TEST'
username = ENV['DSPACE_REST_USERNAME']
password = ENV['DSPACE_REST_PASSWORD']
abort 'Staging credentials are missing' if apply && (username.blank? || password.blank?)

# Process-local getters: never persist credentials or replace saved app settings.
settings = {
  dspace_live_username: username, dspace_live_password: password,
  dspace_live_service_document_url: 'https://ys.library.yorku.ca/server/swordv2/servicedocument',
  dspace_live_collection_uri: 'https://ys.library.yorku.ca/server/swordv2/collection/10315/27543',
  dspace_live_collection_title: 'ETD SWORD Deposit',
  dspace_rest_api_url: 'https://ys.library.yorku.ca/server/api'
}
settings.each { |key, value| AppSettings.define_singleton_method(key) { value } }
# Exercise the real asynchronous handoff, with only this process's synthetic job.
DspaceLicenseBundleJob.queue_adapter = :async
ActionMailer::Base.perform_deliveries = false
Rails.application.eager_load! if apply

report_path = Rails.root.join('tmp/staging-sword-pipeline.jsonl')
abort "Prior run exists at #{report_path}; inspect it before any new deposit" if apply && File.exist?(report_path)
report = apply ? File.open(report_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) : nil
emit = lambda do |event, details = {}|
  line = JSON.generate(time: Time.current.iso8601, event: event, **details)
  puts line
  if report
    report.puts(line)
    report.flush
    report.fsync
  end
end

begin
  token = SecureRandom.hex(6)
  thesis = export_log = nil
  original_hash = nil
  ActiveRecord::Base.transaction do
    student = Student.create!(username: "etd-test-#{token}", name: 'ETD Synthetic Test',
                              email: "etd-test-#{token}@example.com", role: User::STUDENT,
                              sisid: "T#{SecureRandom.hex(4)}")
    thesis = Thesis.create!(student: student, title: "ETD licence pipeline test #{token}",
                            author: 'Synthetic test author - not a real student',
                            supervisor: 'Synthetic test supervisor', gem_record_event_id: 0,
                            degree_name: 'MA', degree_level: Thesis::MASTERS,
                            program: 'Synthetic staging test', language: 'English',
                            exam_date: Date.current, status: Thesis::ACCEPTED, embargoed: false,
                            abstract: 'Synthetic staging-only SWORD and licence automation test. Not a genuine thesis. No student content.')
    Tempfile.create(['etd-synthetic-pipeline-', '.txt']) do |file|
      file.write("Synthetic ETD pipeline test #{token}. Not a genuine thesis. Staging only.\n")
      file.flush
      original_hash = Digest::SHA256.file(file.path).hexdigest
      File.open(file.path) do |payload|
        document = Document.create!(thesis: thesis, user: student, supplemental: true, usage: :thesis,
                                    file: payload)
        # CarrierWave normally stores after commit; rehearse inside a rollback too.
        document.file.store!
      end
    end
    export_log = ExportLog.create!(creator: student, published_date: Date.current,
                                    job_status: ExportLog::JOB_OPEN, production_export: true,
                                    complete_thesis: true, publish_thesis: false,
                                    theses_count: 1, theses_ids: thesis.id.to_s,
                                    successful_count: 0, failed_count: 0)
    # The production flag enables the real hook; every endpoint above is staging.
    job = DspaceExportJob.new
    job.thesis_to_atom_entry(thesis)
    paths = job.extract_thesis_filepaths(thesis)
    raise 'Expected exactly one synthetic file' unless paths.size == 1 && Digest::SHA256.file(paths.first).hexdigest == original_hash
    emit.call('local_inputs_validated', thesis_id: thesis.id, export_log_id: export_log.id, apply: apply)
    raise ActiveRecord::Rollback unless apply
  end

  if apply
    emit.call('deposit_starting', collection: settings.fetch(:dspace_live_collection_uri))
    job = DspaceExportJob.new
    job.sleep_interval = 0
    job.perform(export_log.id)
    export_log.reload
    raise 'SWORD export did not report exactly one success; inspect the local export log' unless export_log.successful_count == 1 && export_log.failed_count == 0
    deposit = DspaceDeposit.find_by!(export_log: export_log, thesis: thesis)
    emit.call('handoff_recorded', item_uuid: deposit.item_uuid, deposit_id: deposit.id)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
    loop do
      deposit.reload
      break if [DspaceDeposit::COMPLETE, DspaceDeposit::FAILED, DspaceDeposit::REVIEW_REQUIRED].include?(deposit.license_status)
      raise 'Licence job did not complete within 60 seconds; do not redeposit' if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      ActiveSupport::Dependencies.interlock.permit_concurrent_loads { sleep 1 }
    end
    emit.call('licence_job_finished', status: deposit.license_status, attempts: deposit.license_attempts)
    raise 'Licence job is not complete; inspect DspaceDeposit.last_error' unless deposit.license_status == DspaceDeposit::COMPLETE

    client = ETD::DspaceRestClient.new(base_url: settings.fetch(:dspace_rest_api_url), username: username, password: password)
    bundles = client.bundles(deposit.item_uuid)
    originals = bundles.select { |bundle| bundle.fetch('name') == 'ORIGINAL' }
    raise 'Expected one ORIGINAL bundle' unless originals.size == 1
    files = client.bitstreams(originals.first.fetch('uuid'))
    raise 'ORIGINAL must contain only the synthetic file' unless files.size == 1 && Digest::SHA256.hexdigest(client.bitstream_content(files.first.fetch('uuid'))) == original_hash
    result = ETD::EnsureLicenseBundle.new(client: client).call(item_uuid: deposit.item_uuid, dry_run: true)
    raise 'Licences are missing' unless result.missing_files.empty?
    streams = client.bitstreams(result.bundle_uuid)
    ETD::LicenseFiles.canonical.each do |file|
      stream = streams.find { |candidate| candidate.fetch('name') == file.fetch(:name) }
      hash = Digest::SHA256.hexdigest(client.bitstream_content(stream.fetch('uuid')))
      accepted = [file, *file.fetch(:existing_variants, [])].map { |version| version.fetch(:sha256) }
      raise 'Licence download hash mismatch' unless accepted.include?(hash)
    end
    attempts = deposit.license_attempts
    DspaceLicenseBundleJob.perform_now(deposit.id)
    raise 'Completed job retried its attachment' unless deposit.reload.license_attempts == attempts
    raise 'Repeat job changed licence bitstreams' unless client.bitstreams(result.bundle_uuid) == streams
    uri = URI("#{settings.fetch(:dspace_rest_api_url)}/core/items/#{deposit.item_uuid}")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) { |http| http.get(uri.request_uri) }
    raise 'Item is not publicly archived; inspect completion/workflow' unless response.code == '200' && JSON.parse(response.body)['inArchive'] == true
    emit.call('validated', item_uuid: deposit.item_uuid, original_sha256: original_hash,
                           licences_verified: true, repeat_job_noop: true, archived: true)
    puts "Inspect https://ys.library.yorku.ca/items/#{deposit.item_uuid}/full"
  else
    puts 'Local rehearsal passed; database rows rolled back. No network requests or deposits made.'
  end
rescue StandardError => error
  emit.call('failed', error_class: error.class.name)
  warn 'Stopped. Do not rerun APPLY: inspect the report and local export/deposit records first.' if apply
  raise
ensure
  report&.close
end
