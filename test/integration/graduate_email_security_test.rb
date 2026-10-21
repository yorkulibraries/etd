# frozen_string_literal: true
require 'test_helper'
require_relative '../support/graduate_email_flow_helpers'
require_relative '../support/graduate_oauth_flow'

# F01-F08 F12-F20: real HTTP/CSRF, durable worker and locked redemption.
# Failure scenarios are recorded in task-5-worklog before product changes.
class GraduateEmailSecurityTest < ActionDispatch::IntegrationTest
  include GraduateEmailFlowHelpers
  include GraduateOAuthFlow
  self.use_transactional_tests = false

  setup do
    setup_flow
    host! '127.0.0.1:3210'
    @forgery = ActionController::Base.allow_forgery_protection
    @app_forgery_inherited = !ApplicationController.config.key?(:allow_forgery_protection)
    @app_forgery = ApplicationController.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    ApplicationController.allow_forgery_protection = true
  end
  teardown do
    ActionController::Base.allow_forgery_protection = @forgery
    if @app_forgery_inherited
      ApplicationController.config.delete(:allow_forgery_protection)
    else
      ApplicationController.allow_forgery_protection = @app_forgery
    end
    teardown_delivery
  end

  test 'csrf_and_oversized_inputs_rejected' do
    get '/graduate/email'
    assert_response :success
    post '/graduate/email/challenges', params: {address: 'approved@example.com'}
    assert_response :unprocessable_entity
    csrf_post '/graduate/email/challenges', address: 'a' * 260
    assert_response :accepted
    csrf_post '/graduate/email/challenges', address: 'x' * 2100
    assert_response :payload_too_large
    assert_equal 0, GraduateEmailChallenge.where.not(student_id: nil).count
  end

  test 'contact_lists_never_enroll_or_receive_codes' do
    @student.update_columns(email: 'approved@example.com,other@example.com')
    csrf_post '/graduate/email/challenges', address: 'approved@example.com'
    assert_response :accepted
    assert_equal 0, GraduateEmailChallenge.where.not(student_id: nil).count
    assert_empty @mail_messages
    assert_raises(GraduateAuthentication::Rejected) { issue_approval(address: 'one@example.com,two@example.com') }
    [false, '1', nil].each do |verified|
      assert_raises(GraduateAuthentication::Rejected) do
        GraduateEmail::Enrollment.issue!(student: @student, actor: @actor, address: 'one@example.com',
          confirmed_address: 'one@example.com', identity_verified: verified, impersonating: false)
      end
    end
    assert_raises(GraduateAuthentication::Rejected) do
      GraduateEmail::Enrollment.issue!(student: @student, actor: @actor, address: 'one@example.com',
        confirmed_address: 'two@example.com', identity_verified: true, impersonating: false)
    end
  end

  test 'pending_email_approval_does_not_replace_google_invitation' do
    google, = GraduateAuthenticationInvitation.issue!(student: @student, approved_by: @actor, provider: 'google_oauth2')
    first, = issue_approval
    second, = issue_approval
    assert first.reload.revoked_at
    assert_nil google.reload.revoked_at
    GraduateEmail::Revocation.approval!(approval: second, actor: @actor, impersonating: false)
    assert second.reload.revoked_at
    assert_nil google.reload.revoked_at
  end

  test 'initial_enrollment_rejects_active_mapping_and_explicit_recovery_preserves_it' do
    enrolled_connection
    before = @mapping.attributes
    assert_raises(GraduateAuthentication::Rejected) { issue_approval }
    recovery, = issue_approval(replacement: true)
    assert_equal @connection.id, recovery.replacement_of_connection_id
    other = create(:student)
    assert_raises(GraduateAuthentication::Rejected) { issue_approval(student: other) }
    assert_equal before, @mapping.reload.attributes
    assert_nil @connection.reload.revoked_at
  end

  test 'cancelled_superseded_expired_or_disabled_approval_cannot_redeem' do
    [:cancel, :supersede, :expired, :disable].each do |operation|
      reset_flow_rows
      sent_enrollment
      case operation
      when :cancel then GraduateEmail::Revocation.approval!(approval: @approval, actor: @actor, impersonating: false)
      when :supersede then issue_approval
      when :expired then travel_to @approval.expires_at
      when :disable then GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
      end
      assert_nil redeem
      assert_equal 0, GraduateEmailActiveAddress.count
      assert_equal 0, GraduateSession.where(authentication_method: 'email').count
      travel_back
    end
  end

  test 'staff_actor_loses_permission_before_redemption' do
    sent_enrollment
    @actor.update!(role: User::STAFF)
    assert_nil redeem
    assert_nil @approval.reload.consumed_at
  end

  # I1: staff turnover never silently disables a verified connection. The
  # pending-approval checks above remain; this login path is approver-independent.
  test 'returning_login_survives_historical_approver_demotion_and_block' do
    sent_enrollment
    grant = redeem
    assert_instance_of GraduateEmail::Grant, grant
    connection = GraduateEmailConnection.find(grant.connection_id)
    assert_equal @actor.id, connection.approved_by_id
    identity = GraduateIdentity.create!(student: @student, linked_by: @actor, provider: 'google_oauth2', uid: 'turnover-google')
    google = GraduateSession.issue!(identity)
    Delayed::Job.delete_all
    durable = [connection.attributes, GraduateEmailActiveAddress.sole.attributes, identity.attributes, Student.count]
    restore = -> { @actor.update!(role: User::MANAGER, blocked: false) }
    demote = -> { @actor.update!(role: User::STAFF) }
    block = -> { @actor.update!(blocked: true) }
    # Mutation before request, between request and worker, and between worker
    # and redemption, through the real HTTP, durable job and RAM transport.
    [[demote, nil, nil], [block, nil, nil], [nil, block, nil], [nil, demote, nil],
      [nil, nil, block], [nil, nil, demote], [demote, block, nil]].each do |before, after_request, after_worker|
      restore.call
      fresh_browser
      host! '127.0.0.1:3210'
      GraduateEmailLimitEvent.where(kind: 'send_address').delete_all
      before&.call
      csrf_post '/graduate/email/challenges', address: connection.normalized_address
      assert_response :accepted
      row = GraduateEmailChallenge.where(purpose: 'login').order(:id).last
      assert_equal 'queued', row&.state
      after_request&.call
      job = Delayed::Job.where(queue: GraduateEmail::Limits::QUEUE).to_a.find { |item| item.payload_object.challenge_public_id == row.public_id }
      @capturing_id = row.public_id
      GraduateAuthenticationMailer.stub(:transport_class, @transport) do
        Delayed::Worker.new(queues: [GraduateEmail::Limits::QUEUE], quiet: true).run(job)
      end
      @capturing_id = nil
      assert_equal 'sent', row.reload.state
      code = otp_code_for(public_id: row.public_id)
      assert code.is_a?(String), 'RAM transport captured code'
      after_worker&.call
      csrf_post '/graduate/email/verify', code: code
      assert_redirected_to student_view_index_path
      assert_equal 'graduate_email', session[:auth_source]
      get student_view_details_path
      assert_response :success
      assert_equal 'consumed', row.reload.state
      assert GraduateSession.valid_for?(grant.session_token, method: 'email', email_connection_id: connection.id,
        generation: 1, student_id: @student.id)
      assert GraduateSession.valid_for?(google, identity_id: identity.id, student_id: @student.id)
      assert_equal durable, [connection.reload.attributes, GraduateEmailActiveAddress.sole.attributes, identity.reload.attributes, Student.count]
    end
    restore.call
    # Pending recovery approval: issued by an authorized approver, then that
    # approver is demoted/blocked before request, worker or redemption.
    [demote, block].each do |change|
      restore.call
      GraduateEmailLimitEvent.where(kind: 'send_address').delete_all
      approval, token = issue_approval(address: 'replacement@example.com', replacement: true)
      browser = SecureRandom.hex(32)
      pending = challenge(GraduateEmail::Challenges.request!(purpose: :enroll, approval_id: approval.id, browser_token: browser, ip: @ip))
      deliver_row(pending)
      code = otp_code_for(public_id: pending.public_id)
      assert code.is_a?(String), 'Pending approval code captured'
      GraduateEmailLimitEvent.where(kind: 'send_address').delete_all
      queued = challenge(GraduateEmail::Challenges.request!(purpose: :enroll, approval_id: approval.id,
        browser_token: SecureRandom.hex(32), ip: @ip))
      claim = GraduateEmail::Delivery.claim!(challenge_public_id: queued.public_id)
      assert claim
      change.call
      GraduateEmailLimitEvent.where(kind: 'send_address').delete_all
      assert_raises(GraduateAuthentication::Rejected) { GraduateEmail::Enrollment.intent!(token: token, browser_token: SecureRandom.hex(32)) }
      assert_equal 'noop', challenge(GraduateEmail::Challenges.request!(purpose: :enroll, approval_id: approval.id,
        browser_token: SecureRandom.hex(32), ip: @ip)).state
      assert_nil GraduateEmail::Delivery.authorize_send!(claim: claim)
      assert_equal 'failed', queued.reload.state
      assert_nil redeem(pending, browser: browser, code: code)
      assert_nil approval.reload.consumed_at
      assert_equal durable[0..1], [connection.reload.attributes, GraduateEmailActiveAddress.sole.attributes]
    end
    restore.call
  end

  test 'forged_target_or_browser_binding_rejected' do
    sent_enrollment
    assert_nil redeem(browser: SecureRandom.hex(32))
    assert_nil redeem(browser: nil)
    get '/graduate/email/verify'
    csrf_post '/graduate/email/verify', challenge_public_id: @row.public_id, student_id: @student.id,
      approval_id: @approval.id, browser_token: @browser, purpose: 'enroll', code: @code
    assert_response :unprocessable_entity
    assert_equal 0, GraduateEmailActiveAddress.count
    assert_instance_of GraduateEmail::Grant, redeem
    assert_nil redeem
  end

  test 'five_failures_resend_aggregate_and_cooldown_are_not_reset' do
    sent_enrollment
    5.times { assert_nil redeem(code: 'bad') }
    assert_equal 5, @row.reload.failed_attempts
    assert_nil redeem
    travel 61.seconds
    second = challenge(GraduateEmail::Challenges.request!(purpose: :enroll, browser_token: @browser,
      approval_id: @approval.id, ip: @ip))
    deliver_row(second)
    code = otp_code_for(public_id: second.public_id)
    4.times { assert_nil redeem(second, code: 'bad') }
    assert_nil redeem(second, code: code)
    assert_equal 10, GraduateEmailLimitEvent.where(kind: 'verify_address').count
    cooldown = GraduateEmailCooldown.find_by!(kind: 'verify_address')
    until_time = cooldown.blocked_until
    assert_nil redeem(second, code: code)
    assert_equal until_time, cooldown.reload.blocked_until
    travel_to until_time
    assert_nil redeem(second, code: code), 'expired challenge cannot revive after cooldown'
  end

  test 'malformed_reused_and_missing_transactions_still_use_global_ip_admission' do
    50.times { assert_nil GraduateEmail::Verification.redeem!(challenge_public_id: nil, browser_token: nil, code: [], ip: @ip) }
    assert_equal 50, GraduateEmailLimitEvent.where(kind: 'verify_ip').count
    assert GraduateEmailCooldown.where(kind: 'verify_ip').exists?
    assert_nil GraduateEmail::Verification.redeem!(challenge_public_id: 'bad', browser_token: nil, code: nil, ip: @ip)
    assert_equal 50, GraduateEmailLimitEvent.where(kind: 'verify_ip').count
    assert_equal 51, GraduateEmailLimitEvent.where(kind: 'admission_verify').count
  end

  test 'exact_five_minute_and_forty_eight_hour_boundaries_and_intent_bound' do
    travel_to Time.current.change(usec: 0)
    sent_enrollment
    travel_to @row.expires_at
    assert_nil redeem
    travel_back
    travel_to @approval.expires_at
    assert_raises(GraduateAuthentication::Rejected) { GraduateEmail::Enrollment.intent!(token: @token, browser_token: @browser) }
    assert_nil redeem
  end

  test 'inflight_stale_mail_after_disable_block_revoke_or_resend_cannot_redeem' do
    [:disable, :block, :revoke, :resend].each do |operation|
      reset_flow_rows
      sent_enrollment
      case operation
      when :disable then GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
      when :block then @student.block
      when :revoke then GraduateEmail::Revocation.approval!(approval: @approval, actor: @actor, impersonating: false)
      when :resend
        travel 61.seconds
        GraduateEmail::Challenges.request!(purpose: :enroll, browser_token: @browser, approval_id: @approval.id, ip: @ip)
      end
      assert_nil redeem
      assert_equal 0, GraduateEmailActiveAddress.count
      travel_back
    end
  end

  test 'concurrent_enrollment_consumes_once' do
    sent_enrollment
    with_redemption_child do |input, marker|
      grant = nil
      GraduateEmail::Control.synchronize do
        # Child has entered redemption while this connection owns control.
        input.puts JSON.generate(id: @row.public_id, browser: @browser, code: @code)
        input.flush
        assert_equal 'RACE_ATTEMPT', marker.call
      end
      grant = redeem
      outcome = marker.call
      assert_equal 1, [!!grant, outcome == 'RACE_ACCEPTED'].count(true)
    end
    assert_equal 1, GraduateEmailActiveAddress.count
    assert_equal 1, GraduateEmailConnection.where(revoked_at: nil).count
    assert_equal 1, GraduateSession.where(authentication_method: 'email', revoked_at: nil).count
    assert @approval.reload.consumed_at
  end

  test 'concurrent_block_and_redemption_has_no_resurrection' do
    [:block, :disable].each do |operation|
      reset_flow_rows
      sent_enrollment
      with_redemption_child do |input, marker|
        if operation == :block
          Student.transaction do
            Student.where(id: @student.id).update_all('blocked = blocked')
            @student.reload.block
            input.puts JSON.generate(id: @row.public_id, browser: @browser, code: @code)
            input.flush
            assert_equal 'RACE_ATTEMPT', marker.call
          end
        else
          GraduateEmail::Control.synchronize do |control|
            control.update!(enabled: false, generation: control.generation + 1)
            input.puts JSON.generate(id: @row.public_id, browser: @browser, code: @code)
            input.flush
            assert_equal 'RACE_ATTEMPT', marker.call
          end
        end
        assert_equal 'RACE_REJECTED', marker.call
      end
      assert_equal 0, GraduateEmailActiveAddress.count
      assert_equal 0, GraduateSession.where(authentication_method: 'email', revoked_at: nil).count
    end
  end

  test 'configured_proxy_ipv6_mapped_peer_and_spoof_fallback_are_canonical' do
    previous = Rails.application.config.action_dispatch.trusted_proxies
    Rails.application.config.action_dispatch.trusted_proxies = [IPAddr.new('2001:db8::/32'), IPAddr.new('192.0.2.0/24')]
    request_class = Struct.new(:peer, :forwarded, :spoof) do
      def get_header(*) = peer
      def remote_ip
        raise ActionDispatch::RemoteIp::IpSpoofAttackError if spoof
        forwarded
      end
    end
    [ ['2001:db8::1', '2001:db9::7', false, '2001:db9::7'],
      ['2001:db9::1', '198.51.100.1', false, '2001:db9::1'],
      ['::ffff:192.0.2.4', '::ffff:198.51.100.5', false, '198.51.100.5'],
      ['2001:db8::1', 'forged', true, '2001:db8::1'] ].each do |peer, forwarded, spoof, expected|
      ip = GraduateEmail::Limits.request_ip(request: request_class.new(peer, forwarded, spoof))
      assert_equal expected, ip
      assert_equal GraduateEmail::Limits.ip_key(input: expected), GraduateEmail::Limits.ip_key(input: ip)
    end
  ensure
    Rails.application.config.action_dispatch.trusted_proxies = previous
  end

  test 'expired_enrollment_cannot_be_renewed_or_switched_by_challenge_post' do
    approval, token = issue_approval
    get '/graduate/email/enroll', params: {token: token}
    follow_redirect!
    travel 10.minutes
    csrf_post '/graduate/email/challenges', address: 'posted@example.com', purpose: 'login'
    assert_response :accepted
    assert_nil session[:graduate_email_intent]['address']
    assert_equal 'enroll', session[:graduate_email_intent]['purpose']
    assert_equal 0, GraduateEmailChallenge.where.not(student_id: nil).count
    assert_nil approval.reload.consumed_at
  end

  test 'resend_keeps_approved_target_and_cross_purpose_and_replay_fail' do
    approval, token = issue_approval
    get '/graduate/email/enroll', params: {token: token}
    follow_redirect!
    csrf_post '/graduate/email/resend', address: 'posted@example.com', approval_id: -1, purpose: 'login'
    assert_response :accepted
    row = GraduateEmailChallenge.where(purpose: 'enroll').last
    assert_equal approval.id, row.approval_id
    deliver_row(row)
    code = otp_code_for(public_id: row.public_id)
    browser = session[:graduate_email_intent]['browser_token']
    assert_nil GraduateEmail::Verification.redeem!(challenge_public_id: row.public_id,
      browser_token: GraduateEmail::Challenges.browser_digest(browser_token: browser, purpose: :login), code: code, ip: @ip)
    csrf_post '/graduate/email/verify', code: code
    assert_redirected_to student_view_index_path
    assert_equal 1, GraduateSession.where(authentication_method: 'email').count
    follow_redirect!
    get '/graduate/email/verify'
    csrf_post '/graduate/email/verify', code: code
    assert_response :unprocessable_entity
    assert_equal 1, GraduateSession.where(authentication_method: 'email').count
  end

  test 'nil_challenge_capacity_and_unknown_send_keep_identical_public_contract' do
    csrf_post '/graduate/email/challenges', address: 'unknown@example.com'
    expected = public_form
    GraduateEmail::Limits.stub(:send_admission, :capacity) do
      get '/graduate/email'
      csrf_post '/graduate/email/challenges', address: 'unknown@example.com'
      assert_equal expected, public_form
    end
    assert_response :accepted
    assert_equal 'no-store', response.headers['Cache-Control']
    assert_equal 'no-referrer', response.headers['Referrer-Policy']
  end

  def public_form
    doc = Nokogiri::HTML(response.body)
    [response.status, doc.css('h1').map(&:text), doc.css('[role="status"]').map(&:text),
      doc.css('main form').map { |form| [form['action'], form.css('input').map { |field| [field['name'], field['type']] }] }]
  end

  test 'no_referrer_null_origin_requires_real_csrf_and_foreign_origin_is_denied' do
    get '/graduate/email'
    token = csrf_token
    post '/graduate/email/challenges', params: {address: 'unknown@example.com'}, headers: {'HTTP_ORIGIN' => 'null'}
    assert_response :unprocessable_entity
    post '/graduate/email/challenges', params: {address: 'unknown@example.com', authenticity_token: token}, headers: {'HTTP_ORIGIN' => 'null'}
    assert_response :accepted
    post '/graduate/email/challenges', params: {address: 'unknown@example.com', authenticity_token: token}, headers: {'HTTP_ORIGIN' => 'https://foreign.example.org'}
    assert_response :unprocessable_entity
  end

  test 'competing_students_same_address_have_one_mapping_and_loser_changes_no_ownership' do
    sent_enrollment
    first_row, first_browser, first_code, first_approval = @row, @browser, @code, @approval
    other = create(:student)
    second_approval, = issue_approval(student: other)
    other_browser = SecureRandom.hex(32)
    GraduateEmail::Control.synchronize do
      GraduateEmailLimitEvent.where(kind: 'send_address').update_all(occurred_at: 61.seconds.ago)
    end
    second = challenge(GraduateEmail::Challenges.request!(purpose: :enroll, browser_token: other_browser,
      approval_id: second_approval.id, ip: @ip))
    deliver_row(second)
    other_code = otp_code_for(public_id: second.public_id)
    assert_operator second.created_at.to_f, :<=, Process.clock_gettime(Process::CLOCK_REALTIME), 'Both process contenders must exist at the real worker clock'
    with_redemption_child do |input, marker|
      GraduateEmail::Control.synchronize do
        input.puts JSON.generate(id: second.public_id, browser: other_browser, code: other_code)
        input.flush
        assert_equal 'RACE_ATTEMPT', marker.call
      end
      grant = redeem(first_row, browser: first_browser, code: first_code)
      outcome = marker.call
      assert_equal 1, [!!grant, outcome == 'RACE_ACCEPTED'].count(true)
    end
    assert_equal 1, GraduateEmailActiveAddress.count
    assert_equal 1, GraduateEmailConnection.count
    assert_equal 1, GraduateSession.where(authentication_method: 'email').count
    winner = GraduateEmailActiveAddress.first.student_id
    [first_approval, second_approval].each do |approval|
      assert_equal approval.student_id == winner, approval.reload.consumed_at.present?
    end
    before = GraduateEmailActiveAddress.first.attributes
    assert_nil redeem(first_row, browser: first_browser, code: first_code)
    assert_nil redeem(second, browser: other_browser, code: other_code)
    assert_equal before, GraduateEmailActiveAddress.first.reload.attributes
  end

  test 'initial_redemption_never_locks_unrelated_google_sessions' do
    sent_enrollment
    unrelated_session_read = false
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      sql = args.last[:sql]
      unrelated_session_read ||= sql.match?(/SELECT.*graduate_sessions.*graduate_email_connection_id.*IS NULL/i)
    end
    assert_instance_of GraduateEmail::Grant, redeem
    refute unrelated_session_read, 'Initial enrollment must not read or lock unrelated Google sessions'
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  test 'production_http_cannot_issue_staff_invitation_or_start_email_flow' do
    ppy_login(@actor)
    get staff_student_graduate_connections_path(@student)
    token = csrf_token
    Rails.env.stub(:production?, true) do
      post student_graduate_email_invitations_path(@student), params: {address: 'approved@example.com',
        confirmed_address: 'approved@example.com', identity_verified: '1', authenticity_token: token}
      assert_response :bad_request
      assert_equal 0, GraduateEmailApproval.count
      get '/graduate/email'
      assert_response :bad_request
    end
  end

  test 'email_http_parameters_filter_recipient_confirmation_code_and_invitation' do
    get '/graduate/email'
    post '/graduate/email/challenges', params: {address: 'parameter-sentinel@example.com',
      confirmed_address: 'confirmation-sentinel@example.com', code: '012345', token: 'INVITATION_SENTINEL', authenticity_token: csrf_token}
    assert_response :accepted
    filtered = request.filtered_parameters
    %w[address confirmed_address code token].each do |name|
      assert_equal '[FILTERED]', filtered[name], 'Authentication inputs must be redacted'
    end
  end

  private

  def with_redemption_child
    require 'open3'
    require 'timeout'
    input, output, waiter = Open3.popen2e(RbConfig.ruby, '-S', 'bundle', 'exec', 'rails', 'runner', 'test/support/graduate_email_redemption_race.rb')
    marker = lambda do
      Timeout.timeout(25) do
        loop do
          line = output.gets
          raise 'Race ended' unless line
          break line.strip if line.start_with?('RACE_')
        end
      end
    end
    assert_equal 'RACE_READY', marker.call
    yield input, marker
    assert Timeout.timeout(25) { waiter.value.success? }, 'independent process completed'
  ensure
    input&.close
    output&.close
    if waiter&.alive?
      Process.kill('KILL', waiter.pid)
      waiter.join(5)
    end
  end

  def csrf_post(path, **params)
    get '/graduate/email' unless response&.body&.include?('csrf-token')
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]('content')
    post path, params: params.merge(authenticity_token: token)
  end

  def reset_flow_rows
    travel_back
    GraduateEmailChallenge.delete_all
    Delayed::Job.delete_all
    GraduateEmailApproval.delete_all
    GraduateEmailLimitEvent.delete_all
    GraduateEmailCooldown.delete_all
    @student.unblock
    GraduateEmailControl.find(1).update!(enabled: true, generation: 1)
  end
end
