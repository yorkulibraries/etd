# frozen_string_literal: true
require 'test_helper'
require 'open3'
require_relative '../support/graduate_oauth_flow'

# F03 F04 F11 F18 F20 F22: storage isolation is necessary to prove DB enforcement.
class GraduateEmailStorageTest < ActionDispatch::IntegrationTest
  include GraduateOAuthFlow
  self.use_transactional_tests = false # committed rows must be visible to independent processes

  def graph
    student = create(:student)
    actor = create(:user, role: User::MANAGER)
    connection = GraduateEmailConnection.create!(student: student, approved_by: actor,
      normalized_address: 'case+tag@example.com', verified_at: Time.current)
    approval = GraduateEmailApproval.create!(student: student, approved_by: actor,
      normalized_address: 'other@example.com', token_digest: SecureRandom.hex(32), generation: 1,
      expires_at: 48.hours.from_now)
    challenge = GraduateEmailChallenge.create!(student: student, approval: approval, purpose: 'enroll',
      public_id: SecureRandom.hex(32), browser_digest: SecureRandom.hex(32), generation: 1,
      expires_at: 5.minutes.from_now, state: 'queued')
    [student, actor, connection, approval, challenge]
  end

  test 'normalization_and_database_equality_agree' do
    normalize = ->(value) { GraduateEmail::Address.normalize(input: value) }
    assert normalize.call(' Case+Tag@Example.COM ') == 'case+tag@example.com', 'canonical equality'
    %W[a@example.com a+b@example.com a.b@example.com ab@example.com].each do |address|
      assert normalize.call(address) == address, 'aliases remain distinct'
    end
    ["a@example.com\r\n", 'a@example.com,b@example.com', 'A <a@example.com>', 'ü@example.com',
     'a@xn--bcher-kva.de', 'a@-example.com', 'a..b@example.com', 'a@localhost', 'a b@example.com'].each do |value|
      assert_nil normalize.call(value), 'unsupported address rejected'
    end
    student, actor, connection = graph
    mapping = GraduateEmailActiveAddress.create!(student: student, connection: connection,
      normalized_address: normalize.call(' Case+Tag@Example.COM '))
    assert GraduateEmailActiveAddress.where(normalized_address: normalize.call('CASE+TAG@example.com')).exists?, 'lookup equality'
    assert mapping.persisted?
  end

  test 'active_mapping_has_two_independent_unique_constraints' do
    student, actor, connection = graph
    GraduateEmailActiveAddress.create!(student: student, connection: connection, normalized_address: connection.normalized_address)
    other = create(:student)
    second = GraduateEmailConnection.create!(student: other, approved_by: actor, normalized_address: 'second@example.com', verified_at: Time.current)
    [{student_id: student.id, connection_id: second.id, normalized_address: 'second@example.com'},
     {student_id: other.id, connection_id: second.id, normalized_address: connection.normalized_address}].each do |row|
      assert_raises(ActiveRecord::RecordNotUnique, 'independent database uniqueness') do
        independent = ActiveRecord::Base.connection_pool.checkout
        begin
          columns = (row.keys + %i[created_at updated_at]).join(', ')
          values = (row.values + [Time.current, Time.current]).map { |value| independent.quote(value) }.join(', ')
          independent.execute("INSERT INTO graduate_email_active_addresses (#{columns}) VALUES (#{values})")
        ensure
          ActiveRecord::Base.connection_pool.checkin(independent) if independent
        end
      end
    end
  end

  test 'session_method_foreign_keys_are_exclusive' do
    student, actor, connection = graph
    identity = GraduateIdentity.create!(student: student, linked_by: actor, provider: 'google_oauth2', uid: 'storage')
    base = { token_digest: SecureRandom.hex(32), expires_at: 12.hours.from_now, created_at: Time.current, updated_at: Time.current }
    [{authentication_method: 'google'}, {authentication_method: 'email', graduate_email_connection_id: connection.id},
     {authentication_method: 'email', graduate_identity_id: identity.id, graduate_email_connection_id: connection.id, email_generation: 1}].each do |invalid|
      assert_raises(ActiveRecord::StatementInvalid, 'exclusive method constraint') { GraduateSession.insert_all!([base.merge(invalid)]) }
    end
    GraduateSession.insert_all!([base.merge(authentication_method: 'email', graduate_email_connection_id: connection.id, email_generation: 1)])
  end

  test 'legacy_issue_insert_uses_persistent_google_default' do
    require_relative '../support/graduate_email_legacy_session'
    student, actor = graph
    identity = GraduateIdentity.create!(student: student, linked_by: actor, provider: 'google_oauth2', uid: 'legacy')
    [GraduateSession, GraduateEmailLegacySession].each do |model|
      token = model.issue!(identity)
      assert token.match?(/\A[0-9a-f]{64}\z/), 'original token format'
      assert GraduateSession.valid_for?(token, identity_id: identity.id, student_id: student.id), 'original session validation'
    end
    column = ActiveRecord::Base.connection.columns(:graduate_sessions).find { |c| c.name == 'authentication_method' }
    assert column.default == 'google' && !column.null, 'persistent database default'
    # Raw SQL bypasses every model attribute default and callback.
    sql = "INSERT INTO graduate_sessions (graduate_identity_id, token_digest, expires_at, created_at, updated_at) VALUES (#{identity.id}, '#{SecureRandom.hex(32)}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
    ActiveRecord::Base.connection.execute(sql)
    assert GraduateSession.order(:id).last.authentication_method == 'google', 'raw insertion default'
  end

  test 'durable_job_survives_process_exit_and_transaction_rollback' do
    job = Delayed::Job.create!(handler: YAML.dump('harmless-storage-payload'), queue: 'storage_sentinel')
    child_check = <<~RUBY
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      expected = ENV['DB_ADAPTER'] == 'sqlite3' ? Rails.root.join('tmp/graduate-email-storage_test.sqlite3').to_s : 'etd_graduate_email_test'
      valid = ENV['DATABASE_URL'] == ENV['TEST_DATABASE_URL'] && config[:adapter] == ENV['DB_ADAPTER'] && config[:database] == expected
      exit(valid && Delayed::Job.where(id: #{job.id}, queue: 'storage_sentinel').exists? ? 0 : 1)
    RUBY
    _, status = Open3.capture2e(RbConfig.ruby, '-S', 'bundle', 'exec', 'rails', 'runner', child_check)
    assert status.success?, 'committed row survives fresh process'
    before = [GraduateEmailChallenge.count, Delayed::Job.count]
    ActiveRecord::Base.transaction do
      graph
      Delayed::Job.create!(handler: YAML.dump('rollback'), queue: 'storage_sentinel')
      raise ActiveRecord::Rollback
    end
    assert [GraduateEmailChallenge.count, Delayed::Job.count] == before, 'rollback is atomic'
  end

  test 'migration_preserves_existing_queue_and_google_session' do
    assert File.file?(Rails.root.join('test/support/graduate_email_storage_probe.rb')), 'migration probe exists'
    %w[priority attempts handler last_error run_at locked_at failed_at locked_by queue created_at updated_at].each do |field|
      assert Delayed::Job.column_names.include?(field), 'existing queue backend field retained'
    end
    assert ActiveRecord::Base.connection.indexes(:delayed_jobs).any? { |index| index.name == 'delayed_jobs_priority' }, 'existing queue index retained'
  end

  test 'audit_references_nullify_without_deleting_policy_history' do
    student, actor, connection, approval, challenge = graph
    audit = GraduateEmailAuditEvent.create!(student: student, actor: actor, connection: connection,
      approval: approval, challenge: challenge, event: 'enrollment', outcome: 'approved', generation: 1)
    [[challenge, :challenge_id], [approval, :approval_id], [connection, :connection_id]].each do |record, key|
      record.delete
      audit.reload
      assert_nil audit.public_send(key), 'deleted reference nullified'
      assert [audit.event, audit.outcome, audit.generation] == ['enrollment', 'approved', 1], 'policy history survives'
    end
    actor.delete
    assert_nil audit.reload.actor_id
    student.delete
    assert_nil audit.reload.student_id
  end

  test 'student_delete_cascades_authentication_without_deleting_audits' do
    student, actor, connection, approval, challenge = graph
    GraduateEmailActiveAddress.create!(student: student, connection: connection, normalized_address: connection.normalized_address)
    audit = GraduateEmailAuditEvent.create!(student: student, actor: actor, approval: approval,
      connection: connection, challenge: challenge, event: 'enrollment', outcome: 'approved', generation: 1)
    historical = GraduateEmailConnection.create!(student: student, approved_by: actor,
      normalized_address: 'historical@example.com', verified_at: Time.current, revoked_at: Time.current)
    GraduateEmailNotice.create!(old_connection: historical, replacement_connection: connection)
    GraduateSession.insert_all!([{graduate_email_connection_id: connection.id, authentication_method: 'email',
      email_generation: 1, token_digest: SecureRandom.hex(32), expires_at: 12.hours.from_now,
      created_at: Time.current, updated_at: Time.current}])
    ppy_login(actor)
    delete student_path(student)
    assert_response :redirect
    refute Student.exists?(student.id), 'actual manager deletion succeeds'
    assert GraduateEmailNotice.count.zero? && GraduateSession.count.zero?, 'dependent notice and email session cascades'
    audit.reload
    assert [audit.student_id, audit.connection_id, audit.approval_id, audit.challenge_id].all?(&:nil?), 'history references nullified'
    assert audit.actor_id == actor.id && audit.generation == 1, 'unrelated history retained'
  end

  test 'runner_rejects_unsafe_configuration_and_propagates_selected_environment' do
    script = Rails.root.join('script/verify_graduate_email_storage').to_s
    [['mysql', {'GRADUATE_EMAIL_TEST_DATABASE_URL' => 'mysql2://invalid/etd_graduate_email_test'}], ['mysql', {'GRADUATE_EMAIL_TEST_DATABASE_URL' => 'mysql2://invalid/etd_graduate_email_test?database=other', 'GRADUATE_EMAIL_TEST_DATABASE_CONFIRMED' => 'dedicated_disposable_test'}], ['mysql', {'GRADUATE_EMAIL_TEST_DATABASE_URL' => 'mysql2://invalid/other_test', 'GRADUATE_EMAIL_TEST_DATABASE_CONFIRMED' => 'dedicated_disposable_test'}], ['invalid', {}]].each do |adapter, extra|
      output, status = Open3.capture2e({'GRADUATE_EMAIL_TEST_DATABASE_URL' => nil}.merge(extra), 'bash', script, adapter, 'exec', 'false')
      refute status.success?, 'unsafe configuration rejected'
      refute output.include?('mysql2://'), 'errors contain no URL'
    end
    code = 'exit(ENV["DATABASE_URL"] == ENV["TEST_DATABASE_URL"] && ENV["SCHEMA"].start_with?(Dir.pwd + "/tmp/") ? 0 : 1)'
    _, status = Open3.capture2e({'DATABASE_URL' => 'sqlite3:/unsafe/application.sqlite3', 'TEST_DATABASE_URL' => 'stale'}, 'bash', script, 'sqlite', 'exec', RbConfig.ruby, '-e', code)
    assert status.success?, 'child environment overrides stale test URL'
  end
end
