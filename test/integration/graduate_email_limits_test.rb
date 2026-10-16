# frozen_string_literal: true
require 'test_helper'
require 'ipaddr'
require_relative '../support/graduate_email_admission_helpers'

# F07-F13 F18 F21: necessary isolated database/worker admission checks, before code.
class GraduateEmailLimitsTest < ActionDispatch::IntegrationTest
  include GraduateEmailAdmissionHelpers
  self.use_transactional_tests = false
  setup { setup_admission }
  teardown { teardown_admission }

  test 'rolling_send_limits_do_not_reset_on_resend' do
    travel_to @instant
    first = request_code
    assert_equal 'queued', challenge(first).state
    travel_to @instant + 59.seconds
    assert_equal first.challenge_public_id, request_code.challenge_public_id
    assert_equal 1, events('send_address').count
    travel_to @instant + 60.seconds
    assert_equal 'queued', challenge(request_code).state
    assert_equal 'superseded', challenge(first).state
    3.times do |i|
      travel_to @instant + (i + 2).minutes
      assert_equal 'queued', challenge(request_code).state
    end
    travel_to @instant + 5.minutes
    assert_equal 'noop', GraduateEmailChallenge.order(:id).last.state if request_code
    assert_equal 5, events('send_address').count
    travel_to @instant + 1.hour
    assert_equal 'queued', challenge(request_code).state
    assert_equal 6, events('send_address').count
  end

  test 'throttled_request_keeps_existing_challenge' do
    travel_to @instant
    result = request_code
    sent = synthetic_sent(result)
    before = sent.attributes.slice('state', 'code_digest', 'failed_attempts', 'invalidated_at')
    travel_to @instant + 59.seconds
    again = request_code
    assert_equal result.challenge_public_id, again.challenge_public_id
    assert_equal before, sent.reload.attributes.slice(*before.keys)
    assert_equal :allowed, admit_verify
    assert_equal 'noop', GraduateEmailChallenge.order(:id).last.state
    assert_equal 2, events('request_ip').count
    assert_no_difference ['GraduateSession.count', 'GraduateEmailAuditEvent.count'] do
      request_code
    end
    assert_nil @approval.reload.consumed_at
    assert_empty ActionMailer::Base.deliveries
  end

  test 'other_browser_resend_preserves_first_code' do
    travel_to @instant
    first = synthetic_sent(request_code)
    travel_to @instant + 60.seconds
    other = SecureRandom.hex(32)
    second = synthetic_sent(request_code(browser_token: other))
    travel_to @instant + 120.seconds
    request_code(browser_token: other)
    assert_equal 'sent', first.reload.state
    assert_equal 'd' * 64, first.code_digest
    assert_equal 'superseded', second.reload.state
    travel_to @instant + 180.seconds
    enrollment = request_code(purpose: :enroll, approval_id: @approval.id, address: @connection.normalized_address)
    assert_equal @approval.id, challenge(enrollment).approval_id
    assert_equal address_key(@approval.normalized_address), challenge(enrollment).address_key
    assert_equal 'sent', first.reload.state
  end

  test 'verification_budgets_span_enrollment_login_and_replacements' do
    travel_to @instant
    old_key = address_key
    new_key = address_key(@approval.normalized_address)
    5.times { assert_equal :allowed, fail_verify(address: old_key) }
    5.times { assert_equal :allowed, fail_verify(address: new_key) }
    assert_equal :limited, admit_verify(address: new_key, ip: ip_key('192.0.2.2'))
    assert_equal 10, events('verify_student').count
    assert_equal 1, GraduateEmailCooldown.where(kind: 'verify_student').count
    assert_equal 0, GraduateEmailCooldown.where(kind: 'verify_address').count
    # A successful admission neither adds a failure nor clears prior failures.
    assert_equal :allowed, admit_verify(address: old_key, student: nil, ip: ip_key('192.0.2.3'))
    assert_equal 5, events('verify_address').where(key_digest: old_key).count
    request_code
    GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
    GraduateEmail::Control.set_enabled!(enabled: true, actor_id: @actor.id)
    assert_equal 10, events('verify_student').count
    assert_equal :limited, admit_verify
  end

  test 'cooldown_does_not_extend_or_block_student' do
    travel_to @instant
    10.times { assert_equal :allowed, fail_verify }
    assert_equal 2, GraduateEmailCooldown.count
    deadlines = GraduateEmailCooldown.pluck(:blocked_until)
    assert deadlines.all? { |time| time == @instant + 15.minutes }
    travel_to @instant + 14.minutes
    2.times { assert_equal :limited, fail_verify }
    assert_equal deadlines, GraduateEmailCooldown.order(:id).pluck(:blocked_until)
    assert_equal 10, events('verify_address').count
    assert_not @student.reload.blocked?
    travel_to @instant + 15.minutes
    assert_equal :allowed, admit_verify
    assert_equal 0, events('verify_address').count
    assert_equal 0, events('verify_student').count
    assert_equal 10, events('verify_ip').count
    assert_equal :allowed, fail_verify
    assert_equal 1, events('verify_address').count
    # IP has its own fifty-failure threshold, independent of target existence.
    other_ip = ip_key('198.51.100.9')
    50.times { assert_equal :allowed, fail_verify(address: nil, student: nil, ip: other_ip) }
    assert_equal :limited, admit_verify(address: nil, student: nil, ip: other_ip)
    until_at = GraduateEmailCooldown.find_by!(kind: 'verify_ip', key_digest: other_ip).blocked_until
    travel_to until_at
    assert_equal :allowed, admit_verify(address: nil, student: nil, ip: other_ip)
    assert_equal 0, events('verify_ip').where(key_digest: other_ip).count
  end

  test 'address_threshold_is_independent_of_student_and_ip' do
    10.times { |i| assert_equal :allowed, fail_verify(student: nil, ip: ip_key("192.0.2.#{i + 10}")) }
    assert_equal :limited, admit_verify(student: nil, ip: ip_key('192.0.2.99'))
    assert_equal 1, GraduateEmailCooldown.where(kind: 'verify_address').count
    assert_equal 0, GraduateEmailCooldown.where(kind: 'verify_student').count
  end

  test 'unknown_and_limited_paths_enqueue_one_noop' do
    travel_to @instant
    20.times do |i|
      result = request_code(address: i.even? ? 'unknown@example.com' : 'invalid', browser_token: SecureRandom.hex(32))
      row = challenge(result)
      assert_equal 'noop', row.state
      assert_nil row.student_id
      assert_nil row.address_key
      assert_nil row.approval_id
      assert_nil row.connection_id
    end
    assert_equal 20, events('request_ip').count
    assert_equal 0, events('send_address').count
    assert_equal 20, Delayed::Job.where(queue: 'graduate_email').count
    assert_difference ['GraduateEmailChallenge.count', 'Delayed::Job.count', "events('admission_send').count"], 1 do
      request_code(address: @connection.normalized_address)
    end
    assert_equal 20, events('request_ip').count
    assert_equal 0, events('send_address').count
    assert_equal 'noop', GraduateEmailChallenge.order(:id).last.state
    assert_equal 0, GraduateEmailAuditEvent.count
    assert_equal 0, GraduateEmailCooldown.count
  end

  test 'global_admission_bounds_queue_and_key_cardinality' do
    travel_to @instant
    # Global send saturation must precede every target lookup.
    120.times { |i| request_code(address: 'invalid', ip: "198.51.100.#{i + 1}") }
    assert_equal 120, events('admission_send').count
    GraduateEmailActiveAddress.expects(:find_by).never
    assert_no_difference ['GraduateEmailLimitEvent.count', 'GraduateEmailChallenge.count', 'Delayed::Job.count'] do
      request_code(ip: '203.0.113.1')
    end
    assert_equal 0, events('send_address').count
    assert_equal 120, events('request_ip').count
    travel_to @instant + 1.minute
    # Every retained OTP queue state counts. The separate notice reserve and
    # unrelated queues must not consume OTP capacity.
    Delayed::Job.delete_all
    rows = 499.times.map do |i|
      {handler: YAML.dump(GraduateEmailDeliveryJob.new(SecureRandom.hex(32))), queue: 'graduate_email',
       priority: 0, attempts: 0, created_at: @instant, updated_at: @instant,
       locked_at: i.even? ? @instant : nil, failed_at: i.odd? ? @instant : nil}
    end
    Delayed::Job.insert_all!(rows)
    50.times { Delayed::Job.create!(handler: YAML.dump(1), queue: 'graduate_email_notice') }
    Delayed::Job.create!(handler: YAML.dump(1), queue: 'unrelated')
    request_code(address: 'invalid')
    assert_equal 500, Delayed::Job.where(queue: 'graduate_email').count
    assert_no_difference ['GraduateEmailChallenge.count', 'GraduateEmailLimitEvent.count', 'Delayed::Job.count'] do
      request_code(address: 'new-unknown@example.com', ip: '203.0.113.2')
    end
    300.times { assert_equal :allowed, admit_verify(address: nil, student: nil) }
    assert_no_difference('GraduateEmailLimitEvent.count') { assert_equal :capacity, admit_verify }
    assert_equal 300, events('admission_verify').count
    travel_to @instant + 2.minutes
    assert_equal :allowed, admit_verify
  end

  test 'trusted_ip_ignores_untrusted_forwarded_headers' do
    # Future controller must pass request.remote_ip, never a posted IP/header.
    app = ->(env) { [200, {}, [GraduateEmail::Limits.request_ip(request: ActionDispatch::Request.new(env))]] }
    env = Rack::MockRequest.env_for('/', 'REMOTE_ADDR' => '192.0.2.40', 'HTTP_X_FORWARDED_FOR' => '203.0.113.5')
    remote = ActionDispatch::RemoteIp.new(app, false).call(env).last.first
    assert_equal '192.0.2.40', remote
    trusted = Rack::MockRequest.env_for('/', 'REMOTE_ADDR' => '127.0.0.1', 'HTTP_X_FORWARDED_FOR' => '203.0.113.5')
    assert_equal '203.0.113.5', ActionDispatch::RemoteIp.new(app, false).call(trusted).last.first
    assert_equal ip_key('2001:db8::1'), ip_key('2001:0db8:0000:0000:0000:0000:0000:0001')
    assert_equal ip_key('192.0.2.1'), ip_key('::ffff:192.0.2.1')
    assert_equal ip_key(nil), ip_key('192.0.2.0/24')
    assert_equal ip_key(nil), ip_key({'X-Forwarded-For' => '203.0.113.5'})
    refute_equal address_key, ip_key(@connection.normalized_address)
    21.times { |i| request_code(address: 'invalid', ip: i.even? ? nil : 'invalid') }
    assert_equal 20, events('request_ip').count
  end

  test 'browser_binding_result_and_target_eligibility_are_server_owned' do
    session = {}
    token = GraduateEmail::Challenges.browser_token!(session: session, purpose: :login)
    assert_match(/\A[0-9a-f]{64}\z/, token)
    assert_equal token, GraduateEmail::Challenges.browser_token!(session: session, purpose: :login)
    refute_equal token, GraduateEmail::Challenges.browser_token!(session: session, purpose: :enroll)
    result = request_code
    assert result.frozen?
    assert result.challenge_public_id.frozen?
    assert result.message.frozen?
    assert_equal %i[challenge_public_id message], result.instance_variables.map { |v| v.to_s.delete_prefix('@').to_sym }.sort
    assert_not_includes result.inspect, @browser
    refute_equal Digest::SHA256.hexdigest(@browser), challenge(result).browser_digest
    refute_equal @browser, challenge(result).browser_digest
    assert_equal address_key, address_key(' APPROVED@EXAMPLE.COM ')
    assert_raises(ArgumentError) { request_code(student_id: @student.id) }
    @mapping.delete
    request_code
    assert_equal 'noop', GraduateEmailChallenge.order(:id).last.state
    # No fallback to ordinary editable contact fields.
    @student.update_columns(email: 'contact@example.com')
    request_code(address: 'contact@example.com')
    assert_equal 'noop', GraduateEmailChallenge.order(:id).last.state
    @mapping = GraduateEmailActiveAddress.create!(student: @student, connection: @connection, normalized_address: @connection.normalized_address)
    assert_no_difference('GraduateSession.count') { request_code(purpose: :enroll, approval_id: @approval.id, address: 'attacker@example.com') }
    row = GraduateEmailChallenge.where(purpose: 'enroll').last
    assert_equal @approval.id, row.approval_id
    assert_equal address_key(@approval.normalized_address), row.address_key
    assert_nil @approval.reload.consumed_at
    assert_empty ActionMailer::Base.deliveries
  end

  test 'ineligible_approvals_connections_and_generation_are_noop' do
    [[:revoked_at, @instant], [:consumed_at, @instant], [:expires_at, @instant], [:generation, 2], [:created_at, @instant - 49.hours]].each do |field, value|
      original = @approval[field]
      @approval.update_columns(field => value)
      assert_equal 'noop', challenge(request_code(purpose: :enroll, approval_id: @approval.id)).state
      @approval.update_columns(field => original)
    end
    @actor.update_columns(blocked: true)
    assert_equal 'noop', challenge(request_code).state
    assert_equal 'noop', challenge(request_code(purpose: :enroll, approval_id: @approval.id)).state
    @actor.update_columns(blocked: false)
    @student.update_columns(blocked: true)
    assert_equal 'noop', challenge(request_code).state
    @student.update_columns(blocked: false)
    @connection.update_columns(revoked_at: @instant)
    assert_equal 'noop', challenge(request_code).state
    @connection.update_columns(revoked_at: nil)
    GraduateEmailControl.find(1).update!(enabled: false)
    assert_equal 'noop', challenge(request_code).state
    assert_equal 0, GraduateEmailAuditEvent.count
  end

  test 'failed_enqueue_rolls_back_reservations_and_supersession' do
    travel_to @instant
    first = synthetic_sent(request_code)
    travel_to @instant + 60.seconds
    Delayed::Job.stubs(:enqueue).raises(ActiveRecord::RecordNotSaved)
    assert_no_difference ['GraduateEmailLimitEvent.count', 'GraduateEmailChallenge.count', 'Delayed::Job.count'] do
      result = request_code
      assert_equal first.public_id, result.challenge_public_id
    end
    assert_equal 'sent', first.reload.state
    assert_equal 'd' * 64, first.code_digest
  end

  test 'serialize_reload_and_worker_execute_safe_branches' do
    travel_to @instant
    real = request_code
    noop = request_code(address: 'unknown@example.com', browser_token: SecureRandom.hex(32))
    notices = []
    logger = Object.new
    logger.define_singleton_method(:warn) do |message|
      raise 'Logging inside product transaction' unless ActiveRecord::Base.connection.open_transactions.zero?
      notices << message
    end
    Rails.stubs(:logger).returns(logger)
    jobs = Delayed::Job.where(queue: 'graduate_email').order(:id).map(&:reload)
    jobs.each do |job|
      payload = job.payload_object
      assert_instance_of GraduateEmailDeliveryJob, payload
      assert_equal [:@challenge_public_id], payload.instance_variables
      assert_match(/\A[0-9a-f]{64}\z/, payload.challenge_public_id)
      assert_equal 1, payload.max_attempts
      assert_equal 30, payload.max_run_time
      assert payload.destroy_failed_jobs?
      assert_not_includes job.handler, @connection.normalized_address
      assert_not_includes job.handler, @browser
    end
    assert_equal [2, 0], Delayed::Worker.new(queues: ['graduate_email']).work_off(10)
    assert_equal 0, Delayed::Job.where(queue: 'graduate_email').count
    assert_equal 'failed', challenge(real).state
    assert notices.any? { |line| line.match?(/\Agraduate_email delivery_not_ready(?: challenge_id=\d+)?\z/) }
    assert_nil challenge(real).code_digest
    assert_equal 'noop', challenge(noop).state
    assert_nil @approval.reload.consumed_at
    assert_equal 0, GraduateSession.count
    assert_empty ActionMailer::Base.deliveries
    assert_not GraduateEmail.const_defined?(:Delivery)
    # Duplicate execution never overwrites a terminal state.
    sent = challenge(real)
    sent.update!(state: 'superseded', invalidated_at: Time.current)
    GraduateEmailDeliveryJob.new(sent.public_id).perform
    assert_equal 'superseded', sent.reload.state
    fresh = request_code(address: 'unknown@example.com')
    # This public job is targetless and cannot generate mail even with missing control.
    GraduateEmailControl.delete_all
    GraduateEmailDeliveryJob.new(fresh.challenge_public_id).perform
    assert_empty ActionMailer::Base.deliveries
  end
end
