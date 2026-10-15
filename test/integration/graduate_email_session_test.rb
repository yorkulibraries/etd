# frozen_string_literal: true
require 'test_helper'
require 'timeout'
require 'open3'
require_relative '../support/graduate_oauth_flow'
require_relative '../support/graduate_email_helpers'

# F12-F18 F20: HTTP cookies plus necessary independent database lock isolation.
# Written before Task 2 implementation. Fixtures use only Task 1 storage APIs.
class GraduateEmailSessionTest < ActionDispatch::IntegrationTest
  include GraduateOAuthFlow
  include GraduateEmailHelpers
  self.use_transactional_tests = false

  setup do
    host! '127.0.0.1:3210'
    @actor = create(:user, role: User::MANAGER)
    @student = create(:student)
    @identity = GraduateIdentity.create!(student: @student, linked_by: @actor, provider: 'google_oauth2', uid: SecureRandom.hex(12))
    @connection = GraduateEmailConnection.create!(student: @student, approved_by: @actor,
      normalized_address: 'approved@example.com', verified_at: Time.current)
    @mapping = GraduateEmailActiveAddress.create!(student: @student, connection: @connection,
      normalized_address: @connection.normalized_address)
    @approval = GraduateEmailApproval.create!(student: @student, approved_by: @actor,
      normalized_address: 'pending@example.com', token_digest: SecureRandom.hex(32), generation: 1, expires_at: 48.hours.from_now)
    @challenge = GraduateEmailChallenge.create!(student: @student, approval: @approval, purpose: 'enroll',
      public_id: SecureRandom.hex(32), browser_digest: SecureRandom.hex(32), generation: 1,
      expires_at: 5.minutes.from_now, state: 'queued')
    GraduateEmailControl.delete_all
    GraduateEmailControl.create!(id: 1, enabled: true, generation: 1)
    @old_env = ENV.to_h.slice('GRADUATE_EMAIL_BASE_URL', 'GRADUATE_EMAIL_CODE_KEY', 'GRADUATE_EMAIL_LIMIT_KEY')
    ENV['GRADUATE_EMAIL_BASE_URL'] = 'http://127.0.0.1:3210'
    ENV['GRADUATE_EMAIL_CODE_KEY'] = 'c' * 32
    ENV['GRADUATE_EMAIL_LIMIT_KEY'] = 'l' * 32
    GraduateEmail.configure!
  end

  teardown do
    %w[GRADUATE_EMAIL_BASE_URL GRADUATE_EMAIL_CODE_KEY GRADUATE_EMAIL_LIMIT_KEY].each { |key| ENV.delete(key) }
    ENV.update(@old_env || {})
    GraduateEmail.configure! if GraduateEmail.respond_to?(:configure!)
    travel_back
    Warden.test_reset!
  end

  test 'google_rows_and_cookies_remain_valid' do
    token = GraduateSession.issue!(@identity)
    assert GraduateSession.valid_for?(token, identity_id: @identity.id, student_id: @student.id)
    cookie!(google_markers(token))
    assert_private
    get logout_path
    assert_redirected_to graduate_login_path
    assert_not GraduateSession.valid_for?(token, identity_id: @identity.id, student_id: @student.id)
    assert_equal ['google_oauth2'], GraduateAuthentication::PROVIDERS
  end

  test 'email_requires_active_mapping_generation_and_student' do
    token = issue
    assert valid?(token)
    cookie!(email_markers(token)); assert_private
    assert_not GraduateSession.valid_for?(token, identity_id: @identity.id, student_id: @student.id)
    assert_not GraduateSession.valid_for?(token, email_connection_id: @connection.id, method: 'email', generation: 1, student_id: @actor.id)
    assert_not valid?(token, generation: 2)
    @mapping.update_columns(normalized_address: 'different@example.com')
    assert_not valid?(token)
    assert_raises(GraduateAuthentication::Rejected) { issue }
    @mapping.update_columns(normalized_address: @connection.normalized_address)
    assert valid?(token)
    travel_to GraduateSession.find_by!(token_digest: Digest::SHA256.hexdigest(token)).expires_at.ceil do
      assert_not valid?(token)
    end
    assert_raises(GraduateAuthentication::Rejected) { GraduateSession.issue_email!(connection: @connection, generation: 1) }
    assert_raises(GraduateAuthentication::Rejected) do
      ActiveRecord::Base.transaction { GraduateEmail::Control.synchronize { flunk 'nested control entered' } }
    end
    @connection.update_columns(revoked_at: Time.current)
    assert_not valid?(token)
  end

  test 'malformed_or_mixed_markers_fail_closed' do
    token = issue
    good = email_markers(token)
    [good.merge('auth_source' => 'ppy'), good.except('graduate_email_generation'),
     good.merge('graduate_identity_id' => @identity.id), good.merge('graduate_email_generation' => '1'),
     good.merge('return_to_user_id' => @actor.id), good.merge('graduate_session_token' => []),
     {'graduate_email_connection_id' => @connection.id},
     google_markers(GraduateSession.issue!(@identity)).merge('graduate_email_generation' => 1)].each do |markers|
      cookie!(markers)
      assert_denied
    end
    mixed = good.merge(auth_source: 'ppy')
    assert GraduateSession.marked?(mixed)
    assert_not GraduateSession.valid_markers_for?(mixed, @student)
  end

  test 'disable_reenable_does_not_revive_dormant_browser' do
    token = issue
    cookie!(email_markers(token))
    saved = cookies[Rails.application.config.session_options[:key]]
    generation = GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
    assert_equal 2, generation
    assert_equal 3, GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
    assert_equal 3, GraduateEmail::Control.set_enabled!(enabled: true, actor_id: @actor.id)
    cookies[Rails.application.config.session_options[:key]] = saved
    assert_denied
    assert_not valid?(token)
    assert valid?(issue, generation: 3), 'verified connections may issue fresh sessions after re-enable'
    assert_raises(GraduateAuthentication::Rejected) do
      GraduateEmail::Control.synchronize { GraduateSession.issue_email!(connection: @connection, generation: 1) }
    end
    assert GraduateEmail::Control.enabled?
    assert GraduateEmailAuditEvent.where(event: 'control', actor_id: @actor.id, generation: 3).exists?
    @actor.block
    assert_raises(GraduateAuthentication::Rejected) { GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id) }
    assert_raises(GraduateAuthentication::Rejected) { GraduateEmail::Audit.record!(event: 'secret address', outcome: 'enabled', generation: 3) }
  end

  test 'database_failure_closes_email_only' do
    token = issue
    google = GraduateSession.issue!(@identity)
    GraduateEmailControl.delete_all
    assert_equal false, GraduateEmail::Control.enabled?
    assert_not valid?(token)
    cookie!(email_markers(token)); assert_denied
    cookie!(google_markers(google)); assert_private
    cookie!('user_id' => @student.id, 'auth_source' => 'ppy'); assert_private
    GraduateEmailControl.stubs(:uncached).raises(ActiveRecord::ConnectionNotEstablished)
    assert_equal false, GraduateEmail::Control.enabled?
    assert_not valid?(token)
    assert GraduateSession.valid_for?(google, identity_id: @identity.id, student_id: @student.id)
  end

  test 'block_unblock_does_not_revive_either_graduate_method' do
    token = issue
    google = GraduateSession.issue!(@identity)
    @student.block
    assert_revoked
    @student.unblock
    assert_not valid?(token)
    assert_not GraduateSession.valid_for?(google, identity_id: @identity.id, student_id: @student.id)
    assert GraduateIdentity.exists?(@identity.id), 'Google identity remains independently linked'
    assert_raises(GraduateAuthentication::Rejected) { issue }
    assert GraduateSession.valid_for?(GraduateSession.issue!(@identity), identity_id: @identity.id, student_id: @student.id)
  end

  test 'direct_save_update_and_update_attribute_block_without_control' do
    [:save, :update, :update_attribute, :block].each do |method|
      @student.unblock
      @connection.update_columns(revoked_at: nil)
      GraduateEmailActiveAddress.find_or_create_by!(student: @student, connection: @connection, normalized_address: @connection.normalized_address)
      @approval.update_columns(revoked_at: nil)
      @challenge.update_columns(state: 'queued', invalidated_at: nil)
      GraduateEmailControl.delete_all
      case method
      when :save then @student.blocked = true; @student.save!
      when :update then @student.update!(blocked: true)
      when :update_attribute then @student.update_attribute(:blocked, true)
      else @student.block
      end
      assert_revoked
    end
  end

  test 'controller_block_and_soft_disable_work_with_missing_or_disabled_control' do
    [true, false].each do |missing|
      [[:post, :block_student_path], [:post, :block_user_path], [:delete, :user_path]].each do |verb, route|
        @student.unblock
        @connection.update_columns(revoked_at: nil)
        GraduateEmailActiveAddress.find_or_create_by!(student: @student, connection: @connection, normalized_address: @connection.normalized_address)
        @approval.update_columns(revoked_at: nil)
        @challenge.update_columns(state: 'queued', invalidated_at: nil)
        missing ? GraduateEmailControl.delete_all : GraduateEmailControl.find_or_create_by!(id: 1).update!(enabled: false)
        cookie!('user_id' => @actor.id, 'auth_source' => 'ppy')
        public_send(verb, public_send(route, @student))
        assert_response :redirect
        assert @student.reload.blocked?
        assert_revoked
      end
      # Ordinary student details update must continue to work with the same control state.
      cookie!('user_id' => @actor.id, 'auth_source' => 'ppy')
      patch student_path(@student), params: {student: {name: 'Updated Student'}}
      assert_response :redirect
      assert_equal 'Updated Student', @student.reload.name
    end
  end

  test 'concurrent_block_and_email_or_google_issue_cannot_resurrect' do
    [:email, :google].each do |method|
      [:block_first, :issue_first].each do |order|
        @student.unblock
        @connection.update_columns(revoked_at: nil)
        GraduateEmailActiveAddress.find_or_create_by!(student: @student, connection: @connection, normalized_address: @connection.normalized_address)
        action = order == :block_first ? 'issue' : 'block'
        stdin, stdout, waiter = Open3.popen2e(RbConfig.ruby, '-S', 'bundle', 'exec', 'rails', 'runner',
          'test/support/graduate_email_session_race.rb', method.to_s, action, @student.id.to_s, @connection.id.to_s, @identity.id.to_s, '', JSON.generate(ActiveRecord::Base.connection_db_config.configuration_hash.slice(:adapter, :database)))
        read_marker = lambda do
          Timeout.timeout(20) do
            loop do
              line = stdout.gets
              raise 'Race process ended before barrier' unless line
              break line.strip if line.start_with?('RACE_')
            end
          end
        end
        assert_equal 'RACE_READY', read_marker.call
        token = nil
        operation = proc do
          if order == :block_first
            Student.where(id: @student.id).update_all('blocked = blocked')
            Student.find(@student.id).block
          else
            token = method == :email ? GraduateSession.issue_email!(connection: @connection, generation: 1) : GraduateSession.issue!(@identity)
          end
          stdin.puts 'START'; stdin.flush
          assert_equal 'RACE_ATTEMPT', read_marker.call
        end
        if order == :issue_first && method == :email
          GraduateEmail::Control.synchronize { operation.call }
        else
          Student.transaction { operation.call }
        end
        assert_equal(order == :block_first ? 'RACE_REJECTED' : 'RACE_ACCEPTED', read_marker.call)
        assert Timeout.timeout(20) { waiter.value.success? }, 'independent database process finished'
        if token
          assert GraduateSession.find_by!(token_digest: Digest::SHA256.hexdigest(token)).revoked_at
        end
        assert @student.reload.blocked?
      ensure
        stdin&.close
        stdout&.close
        if waiter&.alive?
          Process.kill('KILL', waiter.pid)
          waiter.join(5)
        end
      end
    end
  end

  test 'email_session_cannot_prepare_ppy_google_link' do
    token = issue
    state = email_markers(token)
    strategy = Struct.new(:name).new('google_oauth2')
    GraduateAuthentication.prepare_intent!('rack.session' => state, 'omniauth.strategy' => strategy)
    assert_equal 'login', state[:graduate_oauth_intent]['mode']
    assert_not GraduateAuthentication.ppy_student_session?(state, @student)
    state['auth_source'] = 'ppy'
    assert_not GraduateAuthentication.ppy_student_session?(state, @student)
  end

  test 'grant_is_redacted_immutable_and_installs_only_after_commit' do
    grant = GraduateEmail::Grant.new(student_id: @student.id, authentication_method: 'email', connection_id: @connection.id, generation: 1, session_token: issue)
    assert grant.frozen?
    assert grant.session_token.frozen?
    assert_not_includes grant.inspect, grant.session_token
    assert_not_includes grant.to_s, grant.session_token
    controller = ApplicationController.new
    controller.set_request!(ActionController::TestRequest.create(ApplicationController))
    controller.request.set_header('rack.session', ActionController::TestSession.new)
    controller.set_response!(ActionDispatch::TestResponse.new)
    assert_no_difference('GraduateSession.count') { assert_nil controller.send(:start_email_authentication_session, grant: grant) }
    assert_equal @connection.id, controller.session[:graduate_email_connection_id]
    assert_equal grant.session_token, controller.session[:graduate_session_token]
    assert_nil controller.session[:graduate_identity_id]
    assert_equal @student.id, controller.session[:user_id]
    assert_raises(GraduateAuthentication::Rejected) do
      ActiveRecord::Base.transaction { controller.send(:start_email_authentication_session, grant: grant) }
    end
    wrong = GraduateEmail::Grant.new(student_id: @actor.id, authentication_method: 'email', connection_id: @connection.id, generation: 1, session_token: grant.session_token)
    assert_raises(GraduateAuthentication::Rejected) { controller.send(:start_email_authentication_session, grant: wrong) }
  end

  test 'configuration_is_independent_validated_and_boot_safe' do
    token = issue
    ['https://user:pass@example.com', 'https://example.com/path', 'https://example.com?secret=x', 'http://example.com'].each do |url|
      ENV['GRADUATE_EMAIL_BASE_URL'] = url
      GraduateEmail.configure!
      assert_equal false, GraduateEmail::Control.enabled?
      assert_not valid?(token)
    end
    ENV['GRADUATE_EMAIL_BASE_URL'] = 'http://127.0.0.1:3210'
    ENV['GRADUATE_EMAIL_CODE_KEY'] = 'short'
    GraduateEmail.configure!
    assert_equal false, GraduateEmail::Control.enabled?
    GraduateEmailControl.expects(:find_by).never
    GraduateEmail.configure!
  end


  test 'email_only_anonymous_redirect_and_logout_clear_all_intents' do
    GraduateAuthentication.stubs(:enabled_providers).returns([])
    assert GraduateAuthentication.available?
    get student_view_details_path
    assert_redirected_to graduate_login_path
    token = issue
    cookie!(email_markers(token).merge('graduate_enrollment' => {'invitation_id' => @approval.id},
      'graduate_email_intent' => {'approval_id' => @approval.id}, 'omniauth.state' => 'test-state'))
    assert_private
    get logout_path
    assert_redirected_to graduate_login_path
    %w[user_id auth_source graduate_email_connection_id graduate_email_generation graduate_session_token graduate_enrollment graduate_email_intent omniauth.state].each do |key|
      assert_nil session[key]
    end
    assert_not valid?(token)
    GraduateEmailControl.delete_all
    assert_not GraduateAuthentication.available?
    get student_view_details_path
    assert_redirected_to login_url
  end

  test 'control_ownership_is_connection_and_transaction_bound_and_first_sql_is_write' do
    seen = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      sql = payload[:sql]
      seen << sql if sql.match?(/\A(?:UPDATE|SELECT)/i)
    end
    retained = nil
    independent = nil
    GraduateEmail::Control.synchronize do |control|
      retained = control
      assert_equal control, GraduateEmail::Control.locked_state!
      assert_match(/\AUPDATE graduate_email_controls SET lock_version/i, seen.first)
      independent = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          assert_raises(GraduateAuthentication::Rejected) { GraduateSession.issue_email!(connection: @connection, generation: 1) }
        end
      end
      Timeout.timeout(10) { independent.value }
    end
    assert retained
    assert_raises(GraduateAuthentication::Rejected) { GraduateEmail::Control.locked_state! }
    ActiveRecord::Base.transaction do
      assert_raises(GraduateAuthentication::Rejected) { GraduateSession.issue_email!(connection: @connection, generation: 1) }
    end
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    independent.kill if independent&.alive?
  end

  test 'email_lock_wait_is_bounded_and_connection_policy_is_restored' do
    db = ActiveRecord::Base.connection
    read_timeout = lambda do
      db.adapter_name == 'SQLite' ? db.select_value('PRAGMA busy_timeout').to_i : db.select_value('SELECT @@SESSION.innodb_lock_wait_timeout').to_i
    end
    original = read_timeout.call
    assert_raises(GraduateAuthentication::Rejected) do
      GraduateEmail::Control.synchronize do
        assert_operator read_timeout.call, :<=, db.adapter_name == 'SQLite' ? 2000 : 2
        raise GraduateAuthentication::Rejected
      end
    end
    assert_equal original, read_timeout.call
  end

  test 'concurrent_disable_and_issue_never_revive_after_reenable' do
    [:disable_first, :issue_first].each do |order|
      GraduateEmail::Control.set_enabled!(enabled: true, actor_id: @actor.id)
      action = order == :disable_first ? 'issue' : 'disable'
      stdin, stdout, waiter = Open3.popen2e(RbConfig.ruby, '-S', 'bundle', 'exec', 'rails', 'runner',
        'test/support/graduate_email_session_race.rb', 'email', action, @student.id.to_s, @connection.id.to_s, @identity.id.to_s, @actor.id.to_s, JSON.generate(ActiveRecord::Base.connection_db_config.configuration_hash.slice(:adapter, :database)))
      marker = lambda do
        Timeout.timeout(20) do
          loop do
            line = stdout.gets
            raise 'Race process ended before barrier' unless line
            break line.strip if line.start_with?('RACE_')
          end
        end
      end
      assert_equal 'RACE_READY', marker.call
      token = nil
      generation = nil
      GraduateEmail::Control.synchronize do |control|
        generation = control.generation
        if order == :disable_first
          control.update!(enabled: false, generation: generation + 1)
        else
          token = GraduateSession.issue_email!(connection: @connection, generation: generation)
        end
        stdin.puts 'START'; stdin.flush
        assert_equal 'RACE_ATTEMPT', marker.call
      end
      assert_equal(order == :disable_first ? 'RACE_REJECTED' : 'RACE_ACCEPTED', marker.call)
      assert Timeout.timeout(20) { waiter.value.success? }, 'independent disable process finished'
      assert_equal false, GraduateEmail::Control.enabled?
      GraduateEmail::Control.set_enabled!(enabled: true, actor_id: @actor.id)
      assert_not valid?(token, generation: generation) if token
    ensure
      stdin&.close
      stdout&.close
      if waiter&.alive?
        Process.kill('KILL', waiter.pid)
        waiter.join(5)
      end
    end
  end

  private

  def issue
    GraduateEmail::Control.synchronize do |control|
      @student.with_lock { GraduateSession.issue_email!(connection: @connection, generation: control.generation) }
    end
  end

  def valid?(token, generation: 1)
    GraduateSession.valid_for?(token, email_connection_id: @connection.id, method: 'email', generation: generation, student_id: @student.id)
  end

  def email_markers(token)
    {'user_id' => @student.id, 'auth_source' => 'graduate_email', 'graduate_email_connection_id' => @connection.id,
     'graduate_email_generation' => 1, 'graduate_session_token' => token}
  end

  def google_markers(token)
    {'user_id' => @student.id, 'auth_source' => 'graduate_oauth', 'graduate_identity_id' => @identity.id, 'graduate_session_token' => token}
  end

  def cookie!(attributes)
    ppy_login(@actor) unless request
    attributes = {'session_id' => SecureRandom.hex(16)}.merge(session.to_hash.slice('session_id')).merge(attributes)
    key = Rails.application.config.session_options[:key]
    jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
    jar.signed_or_encrypted[key] = {value: attributes}
    headers = {}; jar.write(headers)
    cookies.merge(headers['Set-Cookie'], URI.parse('http://127.0.0.1:3210/'))
  end

  def assert_private
    get student_view_details_path
    assert_response :success
  end

  def assert_denied
    get student_view_details_path
    assert_response :redirect
    assert_nil session[:user_id]
    assert_nil session[:graduate_session_token]
  end

  def assert_revoked
    assert @connection.reload.revoked_at
    assert @approval.reload.revoked_at
    assert_equal 'revoked', @challenge.reload.state
    assert_not GraduateEmailActiveAddress.where(student_id: @student.id).exists?
    assert_not GraduateSession.where(revoked_at: nil).exists?
  end
end
