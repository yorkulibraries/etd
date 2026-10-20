# frozen_string_literal: true
require 'json'
require 'digest'
require_relative 'graduate_email_legacy_session'

# Runs without test_helper, pending-schema checks, or any future email service.
module GraduateEmailStorageProbe
  module_function

  def check(value)
    raise 'Storage invariant failed' unless value
  end

  def snapshot_path
    Rails.root.join('tmp/graduate-email', "#{ENV.fetch('DB_ADAPTER') == 'sqlite3' ? 'sqlite' : 'mysql'}-baseline.json")
  end

  def assert_connection
    check(ENV['RAILS_ENV'] == 'test' && ENV['DATABASE_URL'] == ENV['TEST_DATABASE_URL'])
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    if ENV['DB_ADAPTER'] == 'sqlite3'
      check(config[:adapter] == 'sqlite3' && config[:database] == Rails.root.join('tmp/graduate-email-storage_test.sqlite3').to_s)
    else
      check(config[:adapter] == 'mysql2' && config[:database] == 'etd_graduate_email_test')
    end
  end

  def checksum(record)
    Digest::SHA256.hexdigest(JSON.generate(record.attributes.sort.to_h))
  end

  def seed
    return compare if snapshot_path.exist?
    # Baseline-compatible rows avoid factories, feature models and schema loading.
    now = Time.current
    User.insert_all!([{username: 'storage-actor', name: 'Storage Actor', role: User::MANAGER,
      blocked: false, created_at: now, updated_at: now}])
    actor = User.find_by!(username: 'storage-actor')
    User.insert_all!([{username: 'storage-student', name: 'Storage Student', type: 'Student',
      role: User::STUDENT, sisid: '999999991', created_by_id: actor.id, blocked: false,
      created_at: now, updated_at: now}])
    student = Student.find_by!(username: 'storage-student')
    identity = GraduateIdentity.create!(student: student, linked_by: actor, provider: 'google_oauth2', uid: 'storage-baseline')
    token = GraduateEmailLegacySession.issue!(identity)
    session = GraduateSession.find_by!(token_digest: Digest::SHA256.hexdigest(token))
    check(GraduateSession.valid_for?(token, identity_id: identity.id, student_id: student.id))
    # Never execute this payload; it belongs to a separate sentinel queue.
    job = Class.new(ActiveRecord::Base) { self.table_name = 'delayed_jobs' }.create!(
      handler: YAML.dump('harmless baseline'), queue: 'graduate_storage_sentinel', priority: 7,
      attempts: 2, run_at: now.change(usec: 0), locked_by: 'synthetic-owner')
    snapshot_path.write(JSON.generate({student_id: student.id, identity_id: identity.id,
      session_id: session.id, digest: session.token_digest, expires_at: session.expires_at.iso8601(6),
      job_id: job.id, job_checksum: checksum(job)}))
    File.chmod(0o600, snapshot_path)
  end

  def compare
    snapshot = JSON.parse(snapshot_path.read)
    session = GraduateSession.find(snapshot.fetch('session_id'))
    check(session.token_digest == snapshot.fetch('digest'))
    check(session.expires_at.iso8601(6) == snapshot.fetch('expires_at'))
    job_class = Class.new(ActiveRecord::Base) { self.table_name = 'delayed_jobs' }
    check(checksum(job_class.find(snapshot.fetch('job_id'))) == snapshot.fetch('job_checksum'))
    snapshot
  end

  def check_api(snapshot)
    identity = GraduateIdentity.find(snapshot.fetch('identity_id'))
    [GraduateSession, GraduateEmailLegacySession].each do |model|
      model.reset_column_information
      token = model.issue!(identity)
      check(token.match?(/\A[0-9a-f]{64}\z/))
      check(GraduateSession.valid_for?(token, identity_id: identity.id, student_id: identity.student_id))
      session = GraduateSession.find_by!(token_digest: Digest::SHA256.hexdigest(token))
      check((session.expires_at - Time.current - 12.hours).abs < 5)
    end
  end

  def after_up
    seed
    snapshot = compare
    db = ActiveRecord::Base.connection
    column = db.columns(:graduate_sessions).find { |c| c.name == 'authentication_method' }
    check(column.default == 'google' && !column.null)
    check(db.check_constraints(:graduate_sessions).any? { |c| c.name == 'graduate_session_exclusive_method' })
    check(db.foreign_keys(:graduate_email_audit_events).size == 5)
    check(db.foreign_keys(:graduate_email_audit_events).all? { |fk| fk.on_delete == :nullify })
    check_api(snapshot)
    # Independent connection proves that actual SQL uses the persistent default.
    independent = ActiveRecord::Base.connection_pool.checkout
    begin
      independent.execute("INSERT INTO graduate_sessions (graduate_identity_id,token_digest,expires_at,created_at,updated_at) VALUES (#{Integer(snapshot.fetch('identity_id'))},'#{SecureRandom.hex(32)}',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)")
    ensure
      ActiveRecord::Base.connection_pool.checkin(independent) if independent
    end
    # A missing database default MUST break the original insert; restore it even
    # on MySQL where schema DDL is not transactional.
    begin
      db.change_column_default(:graduate_sessions, :authentication_method, nil)
      GraduateEmailLegacySession.reset_column_information
      rejected = false
      begin
        GraduateEmailLegacySession.issue!(GraduateIdentity.find(snapshot.fetch('identity_id')))
      rescue ActiveRecord::StatementInvalid
        rejected = true
      end
      check(rejected)
    ensure
      db.change_column_default(:graduate_sessions, :authentication_method, 'google')
      GraduateEmailLegacySession.reset_column_information
      GraduateSession.reset_column_information
    end
  end

  def call(mode)
    assert_connection
    case mode
    when 'versions' then nil
    when 'clear_probe_fixtures'
      # All seed/up/down/up comparisons have finished. Do not let the first
      # application test inherit sentinel users/sessions/jobs from the probes.
      require 'database_cleaner/active_record'
      DatabaseCleaner.url_allowlist = [%r{.*test.*}]
      DatabaseCleaner.clean_with(:truncation)
    when 'seed_baseline' then seed
    when 'check_after_up' then after_up
    when 'check_after_down'
      check(!ActiveRecord::Base.connection.column_exists?(:graduate_sessions, :authentication_method))
      check(!ActiveRecord::Base.connection.table_exists?(:graduate_email_controls))
      check_api(compare)
    else raise 'Unknown storage probe'
    end
    db = ActiveRecord::Base.connection
    version = db.adapter_name == 'Mysql2' ? db.select_value('SELECT VERSION()').to_s[/\A[\d.]+/] : db.select_value('SELECT sqlite_version()')
    puts "VERSIONS ruby=#{RUBY_VERSION} rails=#{Rails.version} delayed_job=#{Gem.loaded_specs.fetch('delayed_job').version} backend=#{Gem.loaded_specs.fetch('delayed_job_active_record').version} database=#{version}"
    puts "STORAGE_PROBE PASS #{mode}"
  rescue StandardError
    warn "STORAGE_PROBE FAIL #{%w[versions clear_probe_fixtures seed_baseline check_after_up check_after_down].include?(mode) ? mode : 'unknown'}"
    exit 1
  end
end
GraduateEmailStorageProbe.call(ARGV.fetch(0, 'unknown'))
