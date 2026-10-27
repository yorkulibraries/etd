# frozen_string_literal: true
require 'test_helper'
require 'open3'
require 'timeout'
require 'json'
require_relative '../support/graduate_email_admission_helpers'

# F07 F08 F10 F11: independent processes rendezvous before any product transaction.
class GraduateEmailConcurrencyTest < ActionDispatch::IntegrationTest
  include GraduateEmailAdmissionHelpers
  self.use_transactional_tests = false
  setup { setup_admission }
  teardown { teardown_admission }

  test 'two_workers_cannot_exceed_send_budget' do
    assert_send_race
  end

  test 'two_failures_cannot_lose_a_count' do
    8.times { assert_equal :allowed, fail_verify(now: @instant) }
    outputs = race('failure', [@browser, SecureRandom.hex(32)])
    assert_equal 2, outputs.count { |lines| lines.include?('ADMISSION_COUNTED_FAILURE') }
    %w[verify_address verify_student verify_ip].each { |kind| assert_equal 10, events(kind).count }
    assert_equal 2, GraduateEmailCooldown.count
    assert_equal :limited, admit_verify(now: @instant)
    puts 'ADMISSION_COUNTS failure workers=2 failures_per_key=10 cooldowns=2'
  end

  test 'sqlite_write_first_lock_prevents_read_then_write_race' do
    # Also execute on MySQL to prove the common transaction entry protocol.
    assert_send_race
  end

  private

  def assert_send_race
    tokens = [@browser, SecureRandom.hex(32)]
    previous = tokens.map do |token|
      GraduateEmailChallenge.create!(public_id: SecureRandom.hex(32), student: @student,
        connection: @connection, purpose: 'login', state: 'sent', generation: 1,
        browser_digest: GraduateEmail::Challenges.browser_digest(browser_token: token, purpose: :login),
        address_key: address_key, code_digest: 'd' * 64, expires_at: @instant + 5.minutes)
    end
    GraduateEmail::Control.synchronize do
      4.times { events('send_address').create!(key_digest: address_key, occurred_at: @instant - 2.minutes) }
    end
    outputs = race('send', tokens)
    assert_equal 2, outputs.count { |lines| lines.include?('ADMISSION_SENT_REQUEST') }
    assert_equal 5, events('send_address').count
    assert_equal 2, events('request_ip').count
    assert_equal 2, events('admission_send').count
    assert_equal 1, GraduateEmailChallenge.where(state: 'queued').count
    assert_equal 1, GraduateEmailChallenge.where(state: 'noop').count
    assert_equal ['sent', 'superseded'], previous.map { |row| row.reload.state }.sort
    assert_equal 2, Delayed::Job.where(queue: 'graduate_email').count
    assert_equal 4, GraduateEmailChallenge.count
    assert_equal 0, GraduateEmailAuditEvent.count
    puts 'ADMISSION_COUNTS send workers=2 address_events=5 real_jobs=1 noop_jobs=1 retained_jobs=2 retained_challenges=4'
  end

  def race(action, tokens)
    children = []
    tokens.each do |token|
      input, output, waiter = Open3.popen2e(RbConfig.ruby, '-S', 'bundle', 'exec', 'rails', 'runner',
        'test/support/graduate_email_admission_race.rb')
      input.puts JSON.generate(action: action, browser: token, student_id: @student.id, now: @instant.iso8601,
        database: ActiveRecord::Base.connection_db_config.configuration_hash.slice(:adapter, :database))
      input.flush
      children << [input, output, waiter]
    end
    children.each { |_, output, _| assert_equal 'ADMISSION_READY', marker(output) }
    children.each { |input, _, _| input.puts 'START'; input.flush }
    children.map do |_, output, waiter|
      first = marker(output)
      assert_includes ['ADMISSION_SENT_REQUEST', 'ADMISSION_COUNTED_FAILURE'], first
      lines = [first, marker(output)]
      assert_includes lines, 'ADMISSION_WRITE_FIRST'
      assert Timeout.timeout(25) { waiter.value.success? }, 'independent admission process failed'
      lines
    end
  ensure
    (children || []).each do |input, output, waiter|
      input.close unless input.closed?
      output.close unless output.closed?
      if waiter.alive?
        begin
          Process.kill('KILL', waiter.pid)
        rescue Errno::ESRCH
          # The process exited between alive? and kill.
        ensure
          waiter.join(5)
        end
      end
    end
  end

  def marker(output)
    Timeout.timeout(25) do
      loop do
        line = output.gets
        raise 'Admission child ended before marker' unless line
        return line.strip if line.start_with?('ADMISSION_')
      end
    end
  end
end

require_relative '../support/graduate_email_delivery_process_helpers'

# D03-D05 / F09 F10 F12 F14 F18 F20 F22. Process failure cases first.
class GraduateEmailDeliveryConcurrencyTest < ActionDispatch::IntegrationTest
  include GraduateEmailDeliveryHelpers
  include GraduateEmailDeliveryProcessHelpers
  include GraduateOAuthFlow
  self.use_transactional_tests = false
  setup do
    setup_delivery
    @delivery_app_forgery_inherited = !ApplicationController.config.key?(:allow_forgery_protection)
    @delivery_app_forgery = ApplicationController.allow_forgery_protection
    ApplicationController.allow_forgery_protection = true
    @delivery_forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end
  teardown do
    cleanup_delivery_workers
    ActionController::Base.allow_forgery_protection = @delivery_forgery
    if @delivery_app_forgery_inherited
      ApplicationController.config.delete(:allow_forgery_protection)
    else
      ApplicationController.allow_forgery_protection = @delivery_app_forgery
    end
    teardown_delivery
  end

  test('crash_before_claim_can_claim_once') { assert_crash('before_claim_commit', 'queued') }
  test('crash_after_claim_before_smtp_never_retries') { assert_crash('after_claim', 'claimed') }
  test('crash_after_authorization_before_smtp_never_retries') { assert_crash('after_authorization', 'sending') }
  test('crash_after_smtp_acceptance_keeps_sending_code_verifiable') { assert_crash('after_acceptance', 'sending', accepted: true) }
  test('crash_after_sent_before_ack_is_noop') { assert_crash('after_sent', 'sent', accepted: true) }

  test 'stalled_relay_does_not_hold_locks_or_block_disable_student_or_google' do
    %w[disable model_block controller_block resend google connection_revoke approval_revoke].each do |action|
      [false, true].each do |error|
        # New independent fixtures for each invalidation and finalizer outcome.
        cleanup_delivery_workers
        GraduateEmailLimitEvent.delete_all
        GraduateEmailChallenge.delete_all
        Delayed::Job.delete_all
        @student.update_columns(blocked: false)
        @connection.update_columns(revoked_at: nil)
        @approval.update_columns(revoked_at: nil)
        @mapping = GraduateEmailActiveAddress.find_by(student_id: @student.id) ||
          GraduateEmailActiveAddress.create!(student: @student, connection: @connection, normalized_address: @connection.normalized_address)
        GraduateEmailControl.find(1).update!(enabled: true)
        @approval.update_columns(generation: GraduateEmailControl.find(1).generation)
        identity = GraduateIdentity.find_or_create_by!(student: @student, linked_by: @actor, provider: 'google_oauth2', uid: 'delivery-race')
        email_token = GraduateEmail::Control.synchronize do |control|
          GraduateSession.issue_email!(connection: @connection, generation: control.generation)
        end
        generation = GraduateEmailControl.find(1).generation
        if action == 'controller_block'
          ppy_login(@actor)
          get users_path
        end
        row = challenge(request_code(**(action == 'approval_revoke' ? {purpose: :enroll, approval_id: @approval.id} : {})))
        worker = start_delivery_worker(row, hold: true, outcome: error ? 'ERROR' : 'ACCEPT')
        assert_equal 'DELIVERY_NETWORK', delivery_marker(worker)
        assert Timeout.timeout(5) { worker[:received].pop }, 'No RAM transport acceptance'
        assert_equal 'sending', row.reload.state
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        operation = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            case action
            when 'disable' then GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
            when 'model_block' then Student.find(@student.id).block
            when 'controller_block'
              post block_user_path(@student), params: {authenticity_token: csrf_token}
              assert_response :redirect
            when 'resend'
              # Existing admitted event is moved to exact 60s boundary; no sleep.
              GraduateEmailLimitEvent.where(kind: 'send_address').update_all(occurred_at: 61.seconds.ago)
              request_code
            when 'google'
              token = GraduateSession.issue!(identity)
              assert GraduateSession.valid_for?(token, identity_id: identity.id, student_id: @student.id)
            when 'connection_revoke'
              GraduateEmail::Control.synchronize { @connection.lock!; @connection.update_columns(revoked_at: Time.current) }
            when 'approval_revoke'
              GraduateEmail::Control.synchronize { @approval.lock!; @approval.update_columns(revoked_at: Time.current) }
            end
          end
        end
        Timeout.timeout(5) { operation.value }
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        assert_operator elapsed, :<, 5
        stale = row.reload.attributes
        worker[:release] << true
        finish_delivery_worker(worker)
        code = otp_code_for(public_id: row.public_id)
        assert code
        if action == 'google'
          assert_equal error ? 'failed' : 'sent', row.reload.state
          assert_equal !error, eligible?(row)
        else
          assert_equal stale, row.reload.attributes
          refute eligible?(row)
          assert_nil GraduateEmail::Verification.redeem!(challenge_public_id: row.public_id,
            browser_token: @browser, code: code, ip: @ip)
          refute GraduateSession.valid_for?(email_token, method: 'email', email_connection_id: @connection.id,
            generation: generation, student_id: @student.id) unless %w[resend approval_revoke].include?(action)
        end
        assert_equal 1, @mail_messages.count { |message| message.body.decoded.include?(code) }
        puts "DELIVERY_COUNTS responsive_#{action}_#{error ? 'error' : 'success'} within_budget=1"
      ensure
        operation&.kill if operation&.alive?
      end
    end
  end

  test 'stalled_transport_has_ten_second_total_deadline' do
    row = challenge(request_code)
    worker = start_delivery_worker(row, hold: true)
    assert_equal 'DELIVERY_NETWORK', delivery_marker(worker)
    assert Timeout.timeout(5) { worker[:received].pop }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    finish_delivery_worker(worker)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_operator elapsed, :>=, 8
    assert_operator elapsed, :<, 12
    assert_equal 'failed', row.reload.state
    assert_nil row.code_digest
    assert_equal 1, @mail_messages.size
  end
end

require_relative '../support/graduate_email_recovery_helpers'

# R01-R05. Independent sessions, bounded pre-transaction barriers, real clock.
class GraduateEmailRecoveryConcurrencyTest < ActionDispatch::IntegrationTest
  include GraduateEmailRecoveryHelpers
  self.use_transactional_tests = false
  setup do
    setup_delivery
    @approval.destroy!
  end
  teardown { teardown_delivery }

  # D3: the first replacement claim is hidden while the second is issued and
  # sent, recreating a duplicate that only pre-reservation code could produce.
  test 'replacement_address_preexisting_duplicate_race_fails_closed' do
    other, other_connection = second_owner
    first = prepare_replacement
    first[0].update_columns(revoked_at: Time.current)
    GraduateEmailLimitEvent.where(kind: 'send_address').update_all(occurred_at: 61.seconds.ago)
    second = prepare_replacement(student: other)
    first[0].update_columns(revoked_at: nil)
    old_tokens = [email_session, email_session(other_connection)]
    outcomes = recovery_race(verify_input(first), verify_input(second))
    assert_equal 0, outcomes.count('RECOVERY_ACCEPTED')
    assert_equal 0, GraduateEmailActiveAddress.where(normalized_address: 'replacement@example.com').count
    assert_equal 2, GraduateEmailActiveAddress.count
    [first, second].each { |data| assert_nil data[0].reload.consumed_at }
    assert_equal 0, GraduateEmailNotice.count
    assert_equal [true, true], [valid_email?(old_tokens[0]), valid_email?(old_tokens[1], other_connection)]
    GraduateEmail::Revocation.approval!(approval: second[0], actor: @actor, impersonating: false)
    assert recovery_redeem(first)
    assert_equal @student.id, GraduateEmailActiveAddress.find_by!(normalized_address: 'replacement@example.com').student_id
    assert_nil recovery_redeem(second)
  end

  # C07: independent processes released together; control serializes them.
  test 'simultaneous_cross_student_issuance_reserves_once' do
    students = [create(:student), create(:student)]
    2.times do |round|
      address = "contended-#{round}@example.com"
      outcomes = recovery_race(issue_input(students[0], address), issue_input(students[1], "  #{address.upcase}"))
      assert_equal %w[RECOVERY_ACCEPTED RECOVERY_REJECTED], outcomes.sort, "round #{round}"
      assert_equal 1, live_claims(address).count, "round #{round}"
    end
  end

  # C08: issuance against redemption, cancellation and replacement.
  test 'issuance_races_redemption_cancel_and_replacement_without_two_claims' do
    claimant = create(:student)
    first = prepare_replacement
    outcomes = recovery_race(verify_input(first), issue_input(claimant, 'replacement@example.com'))
    assert_equal %w[RECOVERY_ACCEPTED RECOVERY_REJECTED], outcomes
    assert_equal @student.id, GraduateEmailActiveAddress.find_by!(normalized_address: 'replacement@example.com').student_id
    assert_equal 0, GraduateEmailApproval.where(student_id: claimant.id).count
    pending, = issue_approval(student: create(:student), address: 'canceled@example.com')
    outcomes = recovery_race({action: 'cancel', approval: pending.id, actor: @actor.id}, issue_input(claimant, 'canceled@example.com'))
    assert_equal 'RECOVERY_ACCEPTED', outcomes[0]
    assert pending.reload.revoked_at
    assert_equal(outcomes[1] == 'RECOVERY_ACCEPTED' ? 1 : 0, GraduateEmailApproval.where(student_id: claimant.id).count)
    assert_operator live_claims('canceled@example.com').count, :<=, 1
    other, other_connection = second_owner
    outcomes = recovery_race(issue_input(other, 'switch@example.com', replacement: true), issue_input(create(:student), 'switch@example.com'))
    assert_equal %w[RECOVERY_ACCEPTED RECOVERY_REJECTED], outcomes.sort
    assert_equal 1, live_claims('switch@example.com').count
    assert_nil other_connection.reload.revoked_at
    assert_equal 'other-old@example.com', GraduateEmailActiveAddress.find_by!(student_id: other.id).normalized_address
  end

  test 'revoke_verify_and_disable_have_serial_outcomes' do
    data = prepare_replacement
    token = email_session
    outcomes = recovery_race(verify_input(data), {action: 'revoke', connection: @connection.id, actor: @actor.id}, {action: 'disable', actor: @actor.id})
    assert_equal 2, outcomes.drop(1).count('RECOVERY_ACCEPTED')
    assert @connection.reload.revoked_at
    assert_equal false, GraduateEmailControl.find(1).enabled
    assert_nil recovery_redeem(data)
    GraduateEmail::Control.set_enabled!(enabled: true, actor_id: @actor.id)
    refute valid_email?(token)
    assert_nil recovery_redeem(data)
    assert_equal data[0].reload.consumed_at.present? ? 1 : 0, GraduateEmailNotice.count
    assert_operator GraduateEmailActiveAddress.where(student_id: @student.id).count, :<=, 1
  end

  test 'queued_recovery_transport_accepts_without_error' do
    data = prepare_replacement
    GraduateEmailLimitEvent.where(kind: 'send_address').update_all(occurred_at: 61.seconds.ago)
    queued = challenge(GraduateEmail::Challenges.request!(purpose: :enroll, approval_id: data[0].id,
      browser_token: SecureRandom.hex(32), ip: @ip))
    assert_equal 'queued', queued.state
    assert_equal ['RECOVERY_ACCEPTED'], recovery_race({action: 'deliver', id: queued.public_id})
    assert_equal 'sent', queued.reload.state
    assert queued.sent_at, 'RAM transport accepted without a post-delivery exception'
    assert_nil data[0].reload.consumed_at
    assert_equal 0, GraduateSession.count
  end

  test 'approval_reissue_and_queued_delivery_do_not_resurrect' do
    old = email_session
    data = prepare_replacement
    # Keep one delivered code, and a genuinely queued second-browser challenge.
    GraduateEmailLimitEvent.where(kind: 'send_address').update_all(occurred_at: 61.seconds.ago)
    queued = challenge(GraduateEmail::Challenges.request!(purpose: :enroll, approval_id: data[0].id, browser_token: SecureRandom.hex(32), ip: @ip))
    assert_equal 'queued', queued.state
    outcomes = recovery_race({action: 'reissue', student: @student.id, actor: @actor.id}, {action: 'deliver', id: queued.public_id})
    assert_equal ['RECOVERY_ACCEPTED', 'RECOVERY_ACCEPTED'], outcomes
    assert data[0].reload.revoked_at
    assert_nil recovery_redeem(data)
    assert valid_email?(old)
    assert_equal 'revoked', data[2].reload.state
    assert_equal 'revoked', queued.reload.state
    assert_nil GraduateEmailApproval.order(:id).last.consumed_at
  end

  test 'address_and_student_limits_survive_recovery' do
    8.times { fail_verify }
    old_address_key = address_key
    data = prepare_replacement
    old_events = GraduateEmailLimitEvent.where(kind: %w[send_address verify_address verify_student]).pluck(:id)
    assert_equal ['RECOVERY_ACCEPTED'], recovery_race(verify_input(data))
    assert_equal old_events.sort, GraduateEmailLimitEvent.where(id: old_events).pluck(:id).sort
    assert_equal 8, GraduateEmailLimitEvent.where(kind: 'verify_address', key_digest: old_address_key).count
    new_connection = GraduateEmailConnection.find(GraduateEmailActiveAddress.find_by!(student_id: @student.id).connection_id)
    # New address still shares the existing student failure budget.
    2.times { fail_verify(address: address_key(new_connection.normalized_address)) }
    assert_equal :limited, admit_verify(address: address_key(new_connection.normalized_address))
    assert_equal 10, GraduateEmailLimitEvent.where(kind: 'verify_student').count
  end

  test 'notice_cap_remaining_one_competing_redemptions_commit_only_one_transition' do
    other, other_connection = second_owner
    first = prepare_replacement
    second = prepare_replacement(student: other, address: 'other-new@example.com')
    tokens = [email_session, email_session(other_connection)]
    fill_notice_queue(49)
    outcomes = recovery_race(verify_input(first), verify_input(second))
    assert_equal 1, outcomes.count('RECOVERY_ACCEPTED')
    assert_equal 50, Delayed::Job.where(queue: 'graduate_email_notice').count
    assert_equal 1, GraduateEmailNotice.count
    assert_equal 1, [first, second].count { |data| data[0].reload.consumed_at.present? }
    [first, second].each_with_index do |data, index|
      next if data[0].consumed_at
      assert_equal 'sent', data[2].reload.state
      assert valid_email?(tokens[index], index.zero? ? @connection : other_connection)
    end
  end

  private

  def second_owner
    student = create(:student)
    connection = GraduateEmailConnection.create!(student: student, approved_by: @actor, normalized_address: 'other-old@example.com', verified_at: Time.current)
    GraduateEmailActiveAddress.create!(student: student, connection: connection, normalized_address: connection.normalized_address)
    [student, connection]
  end

  def verify_input(data)
    {action: 'verify', id: data[2].public_id, browser: data[3], code: data[4]}
  end

  def issue_input(student, address, replacement: false)
    {action: 'issue', student: student.id, actor: @actor.id, address: address, replacement: replacement}
  end

  def live_claims(address)
    GraduateEmailApproval.where(normalized_address: address, revoked_at: nil, consumed_at: nil)
  end

  def recovery_race(*inputs)
    children = inputs.map do |data|
      input, output, waiter = Open3.popen2e(RbConfig.ruby, '-S', 'bundle', 'exec', 'rails', 'runner', 'test/support/graduate_email_recovery_process.rb')
      input.puts JSON.generate(data)
      input.flush
      [input, output, waiter]
    end
    marker = ->(output) do
      Timeout.timeout(30) do
        loop do
          line = output.gets
          raise 'Recovery child ended' unless line
          break line.strip if line.start_with?('RECOVERY_')
        end
      end
    end
    children.each { |_, output, _| assert_equal 'RECOVERY_READY', marker.call(output) }
    children.each { |input, _, _| input.puts 'START'; input.flush }
    children.map do |_, output, waiter|
      outcome = marker.call(output)
      assert_includes %w[RECOVERY_ACCEPTED RECOVERY_REJECTED], outcome
      assert Timeout.timeout(30) { waiter.value.success? }, 'Recovery child completed'
      outcome
    end
  ensure
    (children || []).each do |input, output, waiter|
      input.close unless input.closed?
      output.close unless output.closed?
      if waiter.alive?
        Process.kill('KILL', waiter.pid) rescue Errno::ESRCH
        waiter.join(5)
      end
    end
  end
end
