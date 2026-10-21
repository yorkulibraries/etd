# frozen_string_literal: true
require 'test_helper'
require_relative '../support/graduate_email_recovery_helpers'
require_relative '../support/graduate_email_delivery_process_helpers'
require 'open3'
require 'json'

# O01-O10. Operations/integration checks written before Task8 implementation.
class GraduateEmailOperationsTest < ActionDispatch::IntegrationTest
  include GraduateEmailRecoveryHelpers
  include GraduateEmailDeliveryProcessHelpers
  self.use_transactional_tests = false
  setup { setup_delivery }
  teardown do
    cleanup_delivery_workers
    teardown_delivery
  end

  test 'missing_keys_or_control_fail_closed' do
    original = ENV.to_h.slice('GRADUATE_EMAIL_BASE_URL', 'GRADUATE_EMAIL_CODE_KEY', 'GRADUATE_EMAIL_LIMIT_KEY', 'GRADUATE_EMAIL_SMTP_ADDRESS')
    [{'GRADUATE_EMAIL_CODE_KEY' => nil}, {'GRADUATE_EMAIL_LIMIT_KEY' => 'short'},
      {'GRADUATE_EMAIL_LIMIT_KEY' => 'c' * 32}, {'GRADUATE_EMAIL_BASE_URL' => 'http://public.example.org'},
      {'GRADUATE_EMAIL_BASE_URL' => 'https://user:secret@example.org'},
      {'GRADUATE_EMAIL_BASE_URL' => 'https://example.org/path'}, {'GRADUATE_EMAIL_SMTP_ADDRESS' => nil}].each do |bad|
      ENV.update(original); ENV.update(bad); GraduateEmail.configure!
      assert_raises(GraduateAuthentication::Rejected) { GraduateEmail::Operations.transition!(enabled: true, operator: @actor.id.to_s) }
      if bad.keys.first != 'GRADUATE_EMAIL_SMTP_ADDRESS'
        assert_no_difference('GraduateEmailChallenge.count') { request_code }
      end
      assert GraduateEmail::Operations.transition!(enabled: false, operator: @actor.id.to_s)
    end
    ENV.update(original); GraduateEmail.configure!
    GraduateEmailControl.delete_all
    assert_raises(GraduateAuthentication::Rejected) { GraduateEmail::Operations.transition!(enabled: true, operator: @actor.id.to_s) }
    assert_equal 'unavailable', GraduateEmail::Operations.status.fetch(:control)
  ensure
    ENV.update(original) if original
    GraduateEmail.configure!
  end

  test 'real_cli_checks_active_operator_and_emits_only_safe_json' do
    [nil, '', '1x', '0', '99999999'].each { |operator| assert_cli('enable', operator, false) }
    @actor.update!(blocked: true); assert_cli('enable', @actor.id.to_s, false)
    @actor.update!(blocked: false, role: User::STAFF); assert_cli('enable', @actor.id.to_s, false)
    assert_cli('enable', @student.id.to_s, false)
    @actor.update!(role: User::MANAGER)
    assert_cli('disable', @actor.id.to_s, true)
    assert_equal 2, GraduateEmailControl.find(1).reload.generation
    assert_cli('disable', @actor.id.to_s, true)
    assert_equal 3, GraduateEmailControl.find(1).reload.generation
    assert_cli('enable', @actor.id.to_s, true)
    assert_equal 3, GraduateEmailControl.find(1).reload.generation
    assert_cli('status', nil, true)
    assert_cli('cleanup', nil, true)
    assert GraduateEmailControl.find(1).reload.enabled
  end

  test 'cleanup_preserves_active_state_and_limits' do
    now = Time.current.change(usec: 0)
    travel_to now
    live = challenge(request_code)
    recent = GraduateEmailChallenge.create!(public_id: SecureRandom.hex(32), browser_digest: 'b'*64,
      purpose: 'noop', state: 'noop', generation: 1, expires_at: now-24.hours+1.second)
    old = GraduateEmailChallenge.create!(public_id: SecureRandom.hex(32), browser_digest: 'b'*64,
      purpose: 'noop', state: 'noop', generation: 1, expires_at: now-24.hours)
    token = email_session
    google = GraduateIdentity.create!(student: @student, linked_by: @actor, provider: 'google_oauth2', uid: 'operations-google')
    GraduateSession.issue!(google)
    keep_sessions = GraduateSession.pluck(:id)
    old_sessions = keep_sessions.map do |id|
      original = GraduateSession.find(id)
      GraduateSession.create!(original.attributes.except('id').merge('token_digest'=>SecureRandom.hex(32), 'expires_at'=>now-24.hours)).id
    end
    old_event = GraduateEmailLimitEvent.create!(kind: 'admission_send', key_digest: 'f'*64, occurred_at: now-2.hours)
    recent_event = GraduateEmailLimitEvent.create!(kind: 'verify_ip', key_digest: 'e'*64, occurred_at: now-2.hours+1.second)
    protected_event = GraduateEmailLimitEvent.create!(kind: 'verify_ip', key_digest: 'a'*64, occurred_at: now-3.hours)
    active = GraduateEmailCooldown.create!(kind:'verify_ip', key_digest:'a'*64, blocked_until:now+1.minute)
    expired = GraduateEmailCooldown.create!(kind:'verify_ip', key_digest:'b'*64, blocked_until:now-2.hours)
    just_expired = GraduateEmailCooldown.create!(kind:'verify_ip', key_digest:'c'*64, blocked_until:now-2.hours+1.second)
    GraduateEmail::Control.set_enabled!(enabled:false, actor_id:@actor.id)
    result = GraduateEmail::Cleanup.call
    assert_equal 1, result.fetch(:challenges)
    assert_equal 2, result.fetch(:sessions)
    assert_equal 1, result.fetch(:cooldowns)
    assert GraduateEmailChallenge.exists?(live.id)
    assert GraduateEmailChallenge.exists?(recent.id)
    refute GraduateEmailChallenge.exists?(old.id)
    assert_equal keep_sessions.sort, GraduateSession.order(:id).pluck(:id)
    refute GraduateSession.where(id:old_sessions).exists?
    assert GraduateEmailLimitEvent.exists?(recent_event.id)
    refute GraduateEmailLimitEvent.exists?(old_event.id)
    assert GraduateEmailLimitEvent.exists?(protected_event.id)
    assert GraduateEmailCooldown.exists?(active.id)
    assert GraduateEmailCooldown.exists?(just_expired.id)
    refute GraduateEmailCooldown.exists?(expired.id)
    assert_equal @connection.id, @mapping.reload.connection_id
    assert @approval.reload
    assert @connection.reload
    assert_equal false, GraduateEmailControl.find(1).enabled
    assert GraduateEmail::Cleanup.call.values.all?(&:zero?)
    travel_to now+2.hours+1.minute
    GraduateEmail::Cleanup.call
    refute GraduateEmailLimitEvent.exists?(protected_event.id)
    refute GraduateEmailCooldown.exists?(active.id)
  end

  test 'cleanup_successful_audited_challenge_retains_policy_event_and_all_refs_null' do
    row = challenge(request_code)
    row.update!(state:'consumed', consumed_at:Time.current, expires_at:25.hours.ago)
    audit = GraduateEmail::Audit.record!(event:'authentication', outcome:'authenticated', generation:1,
      student_id:@student.id, actor_id:@actor.id, connection_id:@connection.id, approval_id:@approval.id, challenge_id:row.id)
    expected = audit.attributes.slice('event','outcome','generation')
    GraduateEmail::Cleanup.call
    assert_nil audit.reload.challenge_id
    assert_equal expected, audit.attributes.slice(*expected.keys)
    # Existing authorized deletion route is covered by storage suite; exercise
    # actual retained reference FKs individually here as well.
    @student.destroy!
    assert_nil audit.reload.student_id
    assert_nil audit.connection_id
    assert_nil audit.approval_id
    @actor.destroy!
    assert_nil audit.reload.actor_id
    assert_equal expected, audit.attributes.slice(*expected.keys)
  end

  test 'cleanup_is_batched_bounded_and_preserves_other_jobs_and_queued_notices' do
    now = Time.current
    rows = 1101.times.map { {public_id:SecureRandom.hex(32),browser_digest:'b'*64,purpose:'noop',state:'noop',generation:1,failed_attempts:0,expires_at:now-25.hours,created_at:now-26.hours,updated_at:now-26.hours} }
    GraduateEmailChallenge.insert_all!(rows)
    sizes=[]
    sub=ActiveSupport::Notifications.subscribe('sql.active_record') { |*,p| sizes << p[:sql] if p[:sql].start_with?('DELETE') }
    result=GraduateEmail::Cleanup.call
    assert_equal 1101, result.fetch(:challenges)
    assert_operator sizes.count { |sql| sql.include?('graduate_email_challenges') }, :>=, 3
    assert sizes.grep(/graduate_email_challenges/).all? { |sql| ids = sql[/\bIN \(([^)]+)\)/, 1]; ids && ids.split(',').size <= 500 }, 'Every challenge DELETE is bounded'
    assert_operator GraduateEmail::Cleanup::BATCH_SIZE, :<=, 500
    assert_operator GraduateEmail::Cleanup::MAX_BATCHES, :<=, 200
    unrelated=Delayed::Job.enqueue(GraduateEmailDeliveryJob.new(SecureRandom.hex(32)),queue:'default')
    unrelated.update_columns(created_at:3.days.ago,failed_at:3.days.ago)
    replacement=GraduateEmailConnection.create!(student:@student,approved_by:@actor,normalized_address:'new@example.com',verified_at:now)
    queued=GraduateEmailNotice.create!(old_connection:@connection,replacement_connection:replacement,state:'queued')
    job=Delayed::Job.enqueue(GraduateEmailNoticeJob.new(queued.id),queue:'graduate_email_notice')
    job.update_columns(created_at:3.days.ago)
    GraduateEmail::Cleanup.call
    assert Delayed::Job.exists?(unrelated.id)
    assert Delayed::Job.exists?(job.id)
    assert queued.reload
    queued.update_columns(state:'claimed',claimed_at:25.hours.ago,updated_at:25.hours.ago)
    GraduateEmail::Cleanup.call
    refute GraduateEmailNotice.exists?(queued.id)
    refute Delayed::Job.exists?(job.id)
    assert Delayed::Job.exists?(unrelated.id)
  ensure
    ActiveSupport::Notifications.unsubscribe(sub) if sub
  end

  test 'sustained_unknown_and_rejected_traffic_has_bounded_retention' do
    base=Time.current.change(usec:0)
    counts=[]
    4.times do |window|
      travel_to(base+window*26.hours)
      145.times { |n| request_code(address:"unknown#{window}-#{n}@example.com", browser_token:SecureRandom.hex(32),ip:"192.0.2.#{n%250+1}") }
      25.times { |n| request_code(address:"rejected#{n}@example.com",ip:@ip) }
      assert_equal 120, GraduateEmailChallenge.where('created_at >= ?',Time.current).count
      assert_equal 0, GraduateEmailChallenge.where.not(address_key:nil).count
      assert_equal 0, GraduateEmailAuditEvent.count
      assert_equal 1, GraduateEmailActiveAddress.count
      GraduateEmail::Cleanup.call
      counts << [GraduateEmailChallenge.count,GraduateEmailLimitEvent.count,Delayed::Job.where(queue:'graduate_email').count]
      assert_operator counts.last[2], :<=, 500
    end
    assert_equal counts[1],counts[2]
    assert_equal counts[2],counts[3]
  end

  test 'queue_overload_never_mutates_live_challenge_even_without_cleanup' do
    live=challenge(request_code)
    original=live.attributes
    499.times { Delayed::Job.enqueue(GraduateEmailDeliveryJob.new(SecureRandom.hex(32)),queue:'graduate_email') }
    50.times { Delayed::Job.enqueue(GraduateEmailNoticeJob.new(1),queue:'graduate_email_notice') }
    20.times { request_code }
    assert_equal original,live.reload.attributes
    assert_equal 500,Delayed::Job.where(queue:'graduate_email').count
    assert_equal 50,Delayed::Job.where(queue:'graduate_email_notice').count
    assert_equal 1,GraduateEmailChallenge.count
  end

  test 'notice_failure_is_secret_safe_and_metrics_are_counts' do
    @approval.destroy!
    data=prepare_replacement
    assert recovery_redeem(data)
    notice=GraduateEmailNotice.sole
    capture=StringIO.new
    failing=Class.new do
      def initialize(*); end
      def deliver!(message); raise IOError, "NOTICE_SECRET_SENTINEL #{message.encoded}"; end
    end
    Rails.stub(:logger,Logger.new(capture)) do
      GraduateAuthenticationMailer.stub(:transport_class,failing) { GraduateEmailNoticeJob.new(notice.id).perform }
    end
    assert_equal 'failed',notice.reload.state
    assert_safe_absent(capture.string,'NOTICE_SECRET_SENTINEL',@connection.normalized_address,data[1],data[4])
    status=GraduateEmail::Operations.status
    assert_equal 1,status.fetch(:notice_failed)
    assert status.values.all? { |v| v.is_a?(Integer) || %w[enabled disabled unavailable ready unavailable].include?(v) }
    assert_safe_absent(JSON.generate(status),@connection.normalized_address,data[1],data[4])
  end

  test 'disable_command_serializes_with_session_issue' do
    input,output,waiter=Open3.popen2e(cli_env(@actor.id.to_s),RbConfig.ruby,'-S','bundle','exec','rails','runner','test/support/graduate_email_operations_cli.rb')
    marker = -> { Timeout.timeout(30) { loop { line = output.gets; raise 'CLI barrier ended' unless line; break line.strip if line.start_with?('COMMAND_') } } }
    assert_equal 'COMMAND_READY', marker.call
    token=nil
    GraduateEmail::Control.synchronize do |control|
      token=GraduateSession.issue_email!(connection:@connection,generation:control.generation)
      input.puts 'START'; input.flush
      assert_equal 'COMMAND_ATTEMPT', marker.call
    end
    text=Timeout.timeout(30){output.read}
    assert waiter.value.success?
    assert_equal 'disabled',JSON.parse(text.lines.find { |l| l.start_with?('{') }).fetch('control')
    GraduateEmail::Operations.transition!(enabled:true,operator:@actor.id.to_s)
    refute valid_email?(token)
    assert_equal 2,GraduateEmailControl.find(1).reload.generation
  ensure
    [input,output].compact.each { |io| io.close unless io.closed? }
    if waiter&.alive?
      Process.kill('KILL',waiter.pid) rescue Errno::ESRCH
      waiter.join(5)
    end
  end

  test 'production_cookie_configuration_is_explicit' do
    source=Rails.root.join('config/initializers/session_store.rb').read
    assert_match(/secure:.*production\?/,source)
    assert_match(/httponly:\s*true/,source)
    assert_match(/same_site:\s*:lax/,source)
    assert_equal '_etd_session',Rails.application.config.session_options[:key]
  end

  private
  def cli_env(operator)
    {'GRADUATE_EMAIL_OPERATOR_ID'=>operator,'GRADUATE_EMAIL_BASE_URL'=>'https://graduate.example.org',
      'GRADUATE_EMAIL_CODE_KEY'=>'c'*32,'GRADUATE_EMAIL_LIMIT_KEY'=>'l'*32,
      'GRADUATE_EMAIL_FROM'=>'authentication@example.org','GRADUATE_EMAIL_SMTP_ADDRESS'=>'relay.example.org',
      'GRADUATE_EMAIL_SMTP_PORT'=>'587','GRADUATE_EMAIL_SMTP_TLS'=>'starttls'}
  end
  def assert_cli(action,operator,success)
    output,status=Open3.capture2e(cli_env(operator),RbConfig.ruby,'-S','bundle','exec','rails',"graduate_email:#{action}")
    assert_equal success,status.success?, 'CLI exit matches authorized outcome'
    line=output.lines.find { |l| l.start_with?('{') }
    assert line,'CLI returns safe JSON'
    parsed=JSON.parse(line)
    assert parsed.values.all? { |v| v.is_a?(Integer) || %w[enabled disabled unavailable ready rejected ok].include?(v) }
    assert_safe_absent(output,@connection.normalized_address,@approval.token_digest,'mysql2://','sqlite3:')
  end
end
