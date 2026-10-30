# frozen_string_literal: true
require 'test_helper'
require 'stringio'
require 'exception_notifier'
require_relative '../support/graduate_email_delivery_helpers'

# D01-D08 / F05 F09-F14 F18 F20-F23. Written before delivery implementation.
class GraduateEmailDeliveryTest < ActionDispatch::IntegrationTest
  include GraduateEmailDeliveryHelpers
  self.use_transactional_tests = false
  setup { setup_delivery }
  teardown { teardown_delivery }

  test 'job_payload_contains_identifier_only' do
    row = challenge(request_code)
    job = Delayed::Job.where(queue: 'graduate_email').first.reload
    payload = job.payload_object
    assert_equal [:@challenge_public_id], payload.instance_variables
    assert_equal row.public_id, payload.challenge_public_id
    assert_equal [1, 30, true], [payload.max_attempts, payload.max_run_time, payload.destroy_failed_jobs?]
    assert_safe_absent(job.handler, @browser, @connection.normalized_address)
    @capturing_id = row.public_id
    GraduateAuthenticationMailer.stub(:transport_class, @transport) do
      assert_equal [1, 0], Delayed::Worker.new(queues: ['graduate_email']).work_off(1)
    end
    assert_equal 'sent', row.reload.state
    assert_empty Delayed::Job.where(queue: 'graduate_email')
    assert_equal 1, @mail_messages.size
    assert_nil @approval.reload.consumed_at
    assert_equal 0, GraduateSession.count
  end

  test 'code_is_six_digits_including_zero_and_only_keyed_digest_persists' do
    row = challenge(request_code)
    SecureRandom.expects(:random_number).with(1_000_000).returns(42).twice
    deliver_row(row)
    code = otp_code_for(public_id: row.public_id)
    assert code.is_a?(String) && code.match?(/\A0{4}42\z/), 'Code formatting failed'
    assert_nil otp_code_for(public_id: row.public_id)
    assert matches?(row, code)
    assert eligible?(row)
    refute_equal Digest::SHA256.hexdigest(code), row.code_digest
    assert_safe_absent(row.attributes.inspect, code, @browser)
    %w[purpose public_id browser_digest generation connection_id].each do |field|
      copy = row.dup
      copy[field] = row[field].is_a?(Integer) ? row[field] + 1 : 'different'
      refute GraduateEmail::Delivery.code_matches?(challenge: copy, code: code)
    end
    %W[short #{code}0].each { |bad| refute matches?(row, bad) }
    refute matches?(row, nil)
    message = @mail_messages.fetch(0)
    assert_equal [@connection.normalized_address], message.to
    assert_equal ['authentication@example.org'], message.from
    assert_nil message.cc
    assert_nil message.bcc
    assert_equal 'text/plain', message.mime_type
    claim = nil
    row2 = challenge(request_code(browser_token: SecureRandom.hex(32), address: 'unknown@example.com'))
    assert_nil GraduateEmail::Delivery.claim!(challenge_public_id: row2.public_id)
    # A real claim is immutable and safe to inspect, queued/claimed cannot verify.
    travel_to @instant + 61.seconds
    row3 = challenge(request_code)
    refute eligible?(row3)
    claim = GraduateEmail::Delivery.claim!(challenge_public_id: row3.public_id)
    assert claim.frozen?
    assert claim.code.frozen?
    assert claim.dup.frozen?
    assert_raises(TypeError) { Marshal.dump(claim) }
    assert_equal '[FILTERED]', claim.as_json
    assert_safe_absent(claim.inspect, claim.code, claim.digest)
    refute eligible?(row3)
    assert_nil GraduateEmail::Delivery.claim!(challenge_public_id: row3.public_id)
    assert_equal 'claimed', row3.reload.state
    assert_equal 0, GraduateSession.count
  end

  test 'queue_delay_never_extends_expiry' do
    travel_to @instant
    row = challenge(request_code)
    deadline = row.expires_at
    travel_to deadline
    deliver_row(row)
    assert_empty @mail_messages
    assert_nil row.reload.code_digest
    refute eligible?(row)
    assert_equal deadline, row.expires_at
  end

  test 'pending_job_disabled_reenabled_sends_nothing' do
    row = challenge(request_code)
    GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
    GraduateEmail::Control.set_enabled!(enabled: true, actor_id: @actor.id)
    deliver_row(row)
    assert_empty @mail_messages
    assert_nil row.reload.code_digest
    refute eligible?(row)
  end

  test 'unknown_noop_never_constructs_mail' do
    row = challenge(request_code(address: 'unknown@example.com'))
    SecureRandom.expects(:random_number).never
    GraduateAuthenticationMailer.expects(:code).never
    deliver_row(row)
    GraduateEmail::Delivery.perform!(challenge_public_id: SecureRandom.hex(32))
    assert_equal 'noop', row.reload.state
    assert_nil row.code_digest
  end

  test 'duplicate_or_recovered_job_never_sends_twice' do
    row = challenge(request_code)
    deliver_row(row)
    before = row.reload.attributes
    2.times { deliver_row(row) }
    assert_equal before, row.reload.attributes
    assert_equal 1, @mail_messages.size
  end

  test 'reported_delivery_error_invalidates_code_not_approval' do
    row = challenge(request_code(purpose: :enroll, approval_id: @approval.id))
    @transport.define_method(:deliver!) { |message| raise IOError, message.encoded }
    deliver_row(row)
    assert_equal 'failed', row.reload.state
    assert_nil row.code_digest
    assert_nil @approval.reload.consumed_at
    assert_equal 0, GraduateSession.count
    refute eligible?(row)
    deliver_row(row)
    assert_empty @mail_messages
  end

  test 'invalidation_before_authorization_prevents_send' do
    # Historical approver turnover is covered separately below (I1).
    mutations = [-> { @student.block },
      -> { @connection.update_columns(revoked_at: Time.current) }, -> { @mapping.delete },
      -> { GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id) }]
    mutations.each do |mutation|
      row = challenge(request_code(browser_token: SecureRandom.hex(32)))
      claim = GraduateEmail::Delivery.claim!(challenge_public_id: row.public_id)
      assert claim
      mutation.call
      assert_nil GraduateEmail::Delivery.authorize_send!(claim: claim)
      refute eligible?(row)
      assert_nil row.reload.code_digest
      # Reset fixtures directly, without future recovery APIs.
      @student.update_columns(blocked: false)
      @actor.update_columns(blocked: false)
      @connection.update_columns(revoked_at: nil)
      @mapping = GraduateEmailActiveAddress.find_by(student_id: @student.id) ||
        GraduateEmailActiveAddress.create!(student: @student, connection: @connection, normalized_address: @connection.normalized_address)
      GraduateEmailControl.find(1).update!(enabled: true)
      GraduateEmailLimitEvent.delete_all
    end
    assert_empty @mail_messages
  end

  # I1: the approver of a verified connection is a historical audit reference.
  # Pending enrollment/recovery approvals still require an authorized approver.
  test 'approver_turnover_denies_pending_enrollment_but_not_verified_login_delivery' do
    [{'blocked' => true}, {'role' => User::STAFF}].each do |change|
      original = @actor.attributes.slice(*change.keys)
      enroll = challenge(request_code(purpose: :enroll, approval_id: @approval.id, browser_token: SecureRandom.hex(32)))
      login = challenge(request_code(browser_token: SecureRandom.hex(32)))
      enroll_claim = GraduateEmail::Delivery.claim!(challenge_public_id: enroll.public_id)
      login_claim = GraduateEmail::Delivery.claim!(challenge_public_id: login.public_id)
      assert enroll_claim && login_claim
      @actor.update_columns(change)
      assert_nil GraduateEmail::Delivery.authorize_send!(claim: enroll_claim)
      assert_equal 'failed', enroll.reload.state
      assert_nil enroll.code_digest
      assert GraduateEmail::Delivery.authorize_send!(claim: login_claim)
      GraduateEmail::Delivery.finalize!(claim: login_claim, outcome: :sent)
      assert_equal 'sent', login.reload.state
      assert matches?(login, login_claim.code)
      assert eligible?(login)
      # A queued login job processed entirely after the change is also sent.
      travel 61.seconds
      queued = challenge(request_code(browser_token: SecureRandom.hex(32)))
      deliver_row(queued)
      assert_equal 'sent', queued.reload.state
      assert_nil @approval.reload.consumed_at
      @actor.update_columns(original)
      GraduateEmailLimitEvent.delete_all
      travel_back
    end
    assert_equal 2, @mail_messages.size
    assert_equal 0, GraduateSession.count
  end

  test 'approval_current_checks_are_repeated_at_authorization' do
    [[:revoked_at, Time.current], [:consumed_at, Time.current], [:expires_at, Time.current],
      [:created_at, 49.hours.ago], [:generation, 2]].each do |field, value|
      row = challenge(request_code(purpose: :enroll, approval_id: @approval.id, browser_token: SecureRandom.hex(32)))
      claim = GraduateEmail::Delivery.claim!(challenge_public_id: row.public_id)
      assert claim
      old = @approval[field]
      GraduateEmail::Control.synchronize { @approval.lock!; @approval.update_columns(field => value) }
      assert_nil GraduateEmail::Delivery.authorize_send!(claim: claim)
      assert_nil row.reload.code_digest
      @approval.update_columns(field => old)
      GraduateEmailLimitEvent.delete_all
    end
  end

  test 'inflight_stale_mail_cannot_authenticate_or_overwrite_terminal_state' do
    %w[consumed revoked superseded expired failed].each do |state|
      row = challenge(request_code(browser_token: SecureRandom.hex(32)))
      claim = GraduateEmail::Delivery.claim!(challenge_public_id: row.public_id)
      assert GraduateEmail::Delivery.authorize_send!(claim: claim)
      row.update!(state: state, code_digest: nil, invalidated_at: Time.current)
      before = row.reload.attributes
      %i[sent failed].each { |outcome| GraduateEmail::Delivery.finalize!(claim: claim, outcome: outcome) }
      assert_equal before, row.reload.attributes
      refute eligible?(row)
      GraduateEmailLimitEvent.delete_all
    end
    row = challenge(request_code(browser_token: SecureRandom.hex(32)))
    claim = GraduateEmail::Delivery.claim!(challenge_public_id: row.public_id)
    assert GraduateEmail::Delivery.authorize_send!(claim: claim)
    GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
    GraduateEmail::Control.set_enabled!(enabled: true, actor_id: @actor.id)
    before = row.reload.attributes
    GraduateEmail::Delivery.finalize!(claim: claim, outcome: :sent)
    assert_equal before, row.reload.attributes
    refute eligible?(row)
  end

  test 'database_failure_after_reported_error_attempts_fresh_conditional_failure' do
    row = challenge(request_code)
    original = GraduateEmail::Delivery.method(:finalize!)
    attempts = 0
    GraduateEmail::Delivery.stub(:finalize!, ->(**args) {
      attempts += 1
      raise ActiveRecord::ConnectionNotEstablished if attempts == 1
      original.call(**args)
    }) do
      @transport.define_method(:deliver!) { |_| raise IOError, 'static synthetic error' }
      deliver_row(row)
    end
    assert_equal 2, attempts
    assert_equal 'failed', row.reload.state
    assert_nil row.code_digest
  end

  test 'debug_instrumentation_and_exception_reporting_do_not_capture_secrets' do
    row = challenge(request_code)
    code = '004242'
    raw = [code, @browser, @connection.normalized_address].join(' ')
    stream = StringIO.new
    logger = ActiveSupport::Logger.new(stream)
    logger.level = Logger::DEBUG
    events = []
    event_names = []
    notifier = []
    ExceptionNotifier.expects(:notify_exception).never
    subscriber = ActiveSupport::Notifications.subscribe(/action_mailer|action_view|sql.active_record/) do |*args|
      event_names << args.first
      events << args.last.except(:connection).inspect
    end
    originals = [Rails.logger, ActiveRecord::Base.logger, ActionMailer::Base.logger, Delayed::Worker.logger]
    Rails.logger = ActiveRecord::Base.logger = ActionMailer::Base.logger = Delayed::Worker.logger = logger
    SecureRandom.expects(:random_number).with(1_000_000).returns(4242)
    @transport.define_method(:deliver!) { |_| raise IOError, raw }
    GraduateEmailDeliveryJob.any_instance.stubs(:error).with { |_, error| notifier << error; true }
    GraduateAuthenticationMailer.stub(:transport_class, @transport) do
      assert_equal [1, 0], Delayed::Worker.new(queues: ['graduate_email']).work_off(1)
    end
    assert_equal 'failed', row.reload.state
    assert_safe_absent(stream.string + events.join + notifier.inspect + Delayed::Job.pluck(:last_error).inspect, code, @browser, @connection.normalized_address)
    refute event_names.any? { |event| %w[deliver.action_mailer process.action_mailer].include?(event) }, 'Unexpected dispatch event'
    safe_error = assert_raises(GraduateAuthentication::Rejected) do
      GraduateAuthenticationMailer.code(recipient: 'invalid', code: code, expires_at: Time.current)
    end
    assert_nil safe_error.cause
    assert_safe_absent(safe_error.inspect, code, @browser, @connection.normalized_address)
    # Other mailers still publish normal events to the same subscriber/logger.
    ActiveSupport::Notifications.instrument('process.action_mailer', mailer: 'OtherMailer', action: 'safe') {}
    assert events.any? { |event| event.include?('OtherMailer') }, 'Other mailer event missing'
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    if originals
      Rails.logger, ActiveRecord::Base.logger, ActionMailer::Base.logger, Delayed::Worker.logger = originals
    end
  end

  test 'renderer_exception_sentinels_do_not_escape_backend_logger_or_notifier' do
    row = challenge(request_code)
    stream = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(stream)
    ExceptionNotifier.expects(:notify_exception).never
    raw = ['004242', @browser, @connection.normalized_address].join(' ')
    GraduateAuthenticationMailer.any_instance.stubs(:render_to_string).raises(RuntimeError, raw)
    GraduateAuthenticationMailer.stub(:transport_class, @transport) do
      assert_equal [1, 0], Delayed::Worker.new(queues: ['graduate_email']).work_off(1)
    end
    assert_equal 'failed', row.reload.state
    assert_safe_absent(stream.string + Delayed::Job.pluck(:last_error).inspect, *raw.split)
    assert_empty @mail_messages
  ensure
    Rails.logger = original if original
  end

  test 'missing_control_finalize_preserves_entire_challenge_row' do
    row = challenge(request_code)
    claim = GraduateEmail::Delivery.claim!(challenge_public_id: row.public_id)
    assert GraduateEmail::Delivery.authorize_send!(claim: claim)
    before = row.reload.attributes
    GraduateEmailControl.delete_all
    assert_raises(GraduateAuthentication::Rejected) { GraduateEmail::Delivery.finalize!(claim: claim, outcome: :sent) }
    assert_equal before, row.reload.attributes
  end

  test 'smtp_configuration_is_dedicated_validated_and_boot_safe' do
    general = ActionMailer::Base.smtp_settings.dup
    GraduateEmailControl.expects(:find_by).never
    GraduateEmail.configure!
    assert GraduateEmail.delivery_configured?
    settings = GraduateEmail.smtp_settings
    assert_operator settings[:open_timeout], :<=, 3
    assert_operator settings[:read_timeout], :<=, 3
    assert_equal 10, GraduateEmail::Delivery::DELIVERY_DEADLINE
    %w[GRADUATE_EMAIL_FROM GRADUATE_EMAIL_SMTP_ADDRESS GRADUATE_EMAIL_SMTP_PORT GRADUATE_EMAIL_SMTP_TLS].each do |key|
      old = ENV[key]
      ENV[key] = "bad\r\nvalue"
      GraduateEmail.configure!
      refute GraduateEmail.delivery_configured?
      ENV[key] = old
    end
    GraduateEmail.configure!
    assert_equal general, ActionMailer::Base.smtp_settings
    # D07: plain Ruby Time is accepted by the builder as well as Rails zoned time.
    deadline = Time.now.getlocal('-05:00')
    message = GraduateAuthenticationMailer.code(recipient: @connection.normalized_address,
      code: '123456', expires_at: deadline)
    assert message.body.decoded.include?(deadline.getutc.strftime('%Y-%m-%d %H:%M:%S UTC')), 'Expiry rendering failed'
    assert_raises(GraduateAuthentication::Rejected) do
      GraduateAuthenticationMailer.code(recipient: 'one@example.com,two@example.com', code: '123456', expires_at: Time.current)
    end
  end

  # Staging test mailboxes (mailcatcher) cannot encrypt. Unencrypted delivery is
  # an explicit opt-in that production's address, public relays and credentials refuse.
  test 'unencrypted_test_relay_is_refused_for_production_public_relays_and_credentials' do
    plain = {'GRADUATE_EMAIL_SMTP_TLS' => 'none', 'GRADUATE_EMAIL_SMTP_ADDRESS' => '10.0.0.196', 'GRADUATE_EMAIL_SMTP_PORT' => '1025'}
    configured = lambda do |overrides = {}|
      ENV.update(plain.merge(overrides))
      GraduateEmail.configure!
      GraduateEmail.delivery_configured?
    end
    assert configured.call('GRADUATE_EMAIL_BASE_URL' => 'https://etdqa.library.yorku.ca'), 'Staging test relay refused'
    settings = GraduateEmail.smtp_settings
    assert_equal [false, false, nil], settings.values_at(:enable_starttls, :enable_starttls_auto, :tls)
    %w[192.168.1.5 172.16.0.9 127.0.0.1].each { |host| assert configured.call('GRADUATE_EMAIL_SMTP_ADDRESS' => host), host }

    %w[https://etd.library.yorku.ca https://ETD.Library.YorkU.ca/].each do |url|
      refute configured.call('GRADUATE_EMAIL_BASE_URL' => url), "Production allowed #{url}"
    end
    ENV['GRADUATE_EMAIL_BASE_URL'] = 'https://etdqa.library.yorku.ca'
    %w[mailcatcher.example.org mailrelay.yorku.ca 8.8.8.8 172.32.0.1 11.0.0.1 10.0.0].each do |host|
      refute configured.call('GRADUATE_EMAIL_SMTP_ADDRESS' => host), "Public or invalid relay allowed: #{host}"
    end
    refute configured.call('GRADUATE_EMAIL_SMTP_USER_NAME' => 'worker', 'GRADUATE_EMAIL_SMTP_PASSWORD' => 'secret',
      'GRADUATE_EMAIL_SMTP_AUTHENTICATION' => 'plain'), 'Credentials sent unencrypted'
    %w[GRADUATE_EMAIL_SMTP_USER_NAME GRADUATE_EMAIL_SMTP_PASSWORD GRADUATE_EMAIL_SMTP_AUTHENTICATION].each { |key| ENV.delete(key) }
    %w[NONE plain off].each { |mode| refute configured.call('GRADUATE_EMAIL_SMTP_TLS' => mode), mode }
    ENV.delete('GRADUATE_EMAIL_BASE_URL')
    refute configured.call, 'Unencrypted allowed without a site address'

    # Production keeps its encrypted relay.
    ENV.update('GRADUATE_EMAIL_BASE_URL' => 'https://etd.library.yorku.ca', 'GRADUATE_EMAIL_SMTP_TLS' => 'starttls',
      'GRADUATE_EMAIL_SMTP_ADDRESS' => 'mailrelay.yorku.ca', 'GRADUATE_EMAIL_SMTP_PORT' => '25')
    GraduateEmail.configure!
    assert GraduateEmail.delivery_configured?
    assert GraduateEmail.smtp_settings[:enable_starttls]
  ensure
    ENV['GRADUATE_EMAIL_BASE_URL'] = 'http://127.0.0.1:3210'
    GraduateEmail.configure!
  end

  # Real SMTP exchange with a mailcatcher-like server that offers no STARTTLS.
  test 'unencrypted_test_relay_delivers_a_real_code_email_without_starttls' do
    server = TCPServer.new('127.0.0.1', 0)
    received = Queue.new
    relay = Thread.new do
      2.times do
        client = server.accept
        client.write("220 test relay\r\n")
        data = nil
        while (line = client.gets)
          if data
            line == ".\r\n" ? (received << data; data = nil; client.write("250 queued\r\n")) : data << line
          elsif line.start_with?('EHLO')
            client.write("250-test relay\r\n250 SIZE 1000000\r\n")
          elsif line.start_with?('DATA')
            data = +''
            client.write("354 go ahead\r\n")
          elsif line.start_with?('QUIT')
            client.write("221 bye\r\n")
            break
          elsif line.start_with?('STARTTLS')
            client.write("502 not supported\r\n")
          else
            client.write("250 OK\r\n")
          end
        end
        client.close
      end
    end
    message = -> { GraduateAuthenticationMailer.code(recipient: @connection.normalized_address, code: '012345', expires_at: 5.minutes.from_now) }
    ENV.update('GRADUATE_EMAIL_SMTP_ADDRESS' => '127.0.0.1', 'GRADUATE_EMAIL_SMTP_PORT' => server.addr[1].to_s,
      'GRADUATE_EMAIL_BASE_URL' => 'https://etdqa.library.yorku.ca')

    ENV['GRADUATE_EMAIL_SMTP_TLS'] = 'starttls'
    GraduateEmail.configure!
    assert_raises(Net::SMTPUnsupportedCommand) { message.call.deliver }

    ENV['GRADUATE_EMAIL_SMTP_TLS'] = 'none'
    GraduateEmail.configure!
    message.call.deliver
    body = Timeout.timeout(5) { received.pop }
    assert_includes body, 'Your sign-in code is 012345.'
  ensure
    relay&.kill
    server&.close
    ENV['GRADUATE_EMAIL_BASE_URL'] = 'http://127.0.0.1:3210'
    GraduateEmail.configure!
  end

  # I2: configuration lost after worker start, or a standalone/default worker run.
  # Durable work becomes visibly terminal; nothing is generated, sent or retried.
  test 'unconfigured_execution_fails_visibly_without_code_or_silent_job_loss' do
    enroll = challenge(request_code(purpose: :enroll, approval_id: @approval.id, browser_token: SecureRandom.hex(32)))
    login = challenge(request_code)
    unknown = challenge(request_code(browser_token: SecureRandom.hex(32), address: 'unknown@example.com'))
    replacement = GraduateEmailConnection.create!(student: @student, approved_by: @actor,
      normalized_address: 'replacement@example.net', verified_at: Time.current)
    notice = GraduateEmailNotice.create!(old_connection: @connection, replacement_connection: replacement)
    Delayed::Job.enqueue(GraduateEmailNoticeJob.new(notice.id), queue: GraduateEmailNoticeJob::QUEUE)
    secret = 'I2_RUNTIME_SENTINEL'
    ENV.update('GRADUATE_EMAIL_SMTP_USER_NAME' => 'worker', 'GRADUATE_EMAIL_SMTP_AUTHENTICATION' => 'plain',
      'GRADUATE_EMAIL_SMTP_PASSWORD' => "#{secret}\r\nRCPT")
    GraduateEmail.configure!
    assert GraduateEmail.configured?
    refute GraduateEmail.delivery_configured?
    stream = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(stream)
    SecureRandom.expects(:random_number).never
    GraduateAuthenticationMailer.expects(:code).never
    GraduateAuthenticationMailer.expects(:access_changed).never
    ExceptionNotifier.expects(:notify_exception).never
    assert_equal [4, 0], Delayed::Worker.new(queues: %w[graduate_email graduate_email_notice], quiet: true).work_off(10)
    [enroll, login].each do |row|
      row.reload
      assert_equal 'failed', row.state
      assert row.invalidated_at
      assert_nil row.code_digest
      assert_nil row.claimed_at
    end
    assert_equal 'noop', unknown.reload.state
    assert_equal 'failed', notice.reload.state
    assert_nil notice.claimed_at
    assert_nil notice.sent_at
    assert_nil @approval.reload.consumed_at
    assert_equal 0, GraduateSession.count
    assert_empty Delayed::Job.where(queue: %w[graduate_email graduate_email_notice])
    assert_empty @mail_messages
    diagnostics = stream.string.lines.map(&:strip).grep(/graduate_email/).sort
    assert_equal ['graduate_email delivery_unconfigured', 'graduate_email delivery_unconfigured',
      'graduate_email notice_unconfigured'], diagnostics
    assert_safe_absent(stream.string, secret, @connection.normalized_address, 'replacement@example.net',
      'pending@example.com', login.public_id)
    status = GraduateEmail::Operations.status
    assert_equal [1, 0], status.values_at(:notice_failed, :notice_stale_queued)
    # Restored configuration and a duplicate job never revive terminal work.
    Rails.logger = original
    %w[GRADUATE_EMAIL_SMTP_USER_NAME GRADUATE_EMAIL_SMTP_AUTHENTICATION GRADUATE_EMAIL_SMTP_PASSWORD].each { |key| ENV.delete(key) }
    GraduateEmail.configure!
    assert GraduateEmail.delivery_configured?
    Delayed::Job.enqueue(GraduateEmailNoticeJob.new(notice.id), queue: GraduateEmailNoticeJob::QUEUE)
    Delayed::Job.enqueue(GraduateEmailDeliveryJob.new(login.public_id), queue: GraduateEmail::Limits::QUEUE)
    GraduateAuthenticationMailer.stub(:transport_class, @transport) do
      assert_equal [2, 0], Delayed::Worker.new(queues: %w[graduate_email graduate_email_notice], quiet: true).work_off(10)
    end
    assert_equal %w[failed failed], [notice.reload.state, login.reload.state]
    assert_empty @mail_messages
  ensure
    Rails.logger = original if original
  end

  test 'notice_claims_once_to_old_recipient_while_disabled_and_failure_never_restores_access' do
    notice = GraduateEmailNotice.create!(old_connection: @connection,
      replacement_connection: GraduateEmailConnection.create!(student: @student, approved_by: @actor,
        normalized_address: 'replacement@example.net', verified_at: Time.current))
    GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
    GraduateEmail::Control.synchronize { @connection.lock!; @connection.update_columns(revoked_at: Time.current); @mapping.delete }
    payload = GraduateEmailNoticeJob.new(notice.id)
    assert_equal [:@notice_id], payload.instance_variables
    assert_equal [1, 30, true], [payload.max_attempts, payload.max_run_time, payload.destroy_failed_jobs?]
    assert_equal 'graduate_email_notice', GraduateEmailNoticeJob::QUEUE
    assert_equal 50, GraduateEmailNoticeJob::QUEUE_CAPACITY
    job = Delayed::Job.enqueue(payload, queue: GraduateEmailNoticeJob::QUEUE).reload
    assert_safe_absent(job.handler, @connection.normalized_address)
    GraduateAuthenticationMailer.stub(:transport_class, @transport) do
      assert_equal [1, 0], Delayed::Worker.new(queues: [GraduateEmailNoticeJob::QUEUE]).work_off(1)
      payload.perform
    end
    assert_equal 'sent', notice.reload.state
    assert_equal 1, @mail_messages.size
    message = @mail_messages.first
    assert_equal [@connection.normalized_address], message.to
    assert_nil message.cc
    assert_nil message.bcc
    assert_safe_absent(message.body.decoded, 'replacement@example.net', 'http', 'code')
    assert @connection.reload.revoked_at
    assert_empty GraduateEmailActiveAddress.where(student_id: @student.id)
    notice.update!(state: 'queued', claimed_at: nil, sent_at: nil)
    @transport.define_method(:deliver!) { |_| raise IOError, 'static failure' }
    GraduateAuthenticationMailer.stub(:transport_class, @transport) { payload.perform; payload.perform }
    assert_equal 'failed', notice.reload.state
    assert_equal 1, @mail_messages.size
    assert @connection.reload.revoked_at
  end
end
