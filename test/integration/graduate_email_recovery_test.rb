# frozen_string_literal: true
require 'test_helper'
require_relative '../support/graduate_email_recovery_helpers'
require_relative '../support/graduate_oauth_flow'

# R01-R07 / F16-F20. Written before Task6 product changes.
class GraduateEmailRecoveryTest < ActionDispatch::IntegrationTest
  include GraduateEmailRecoveryHelpers
  include GraduateOAuthFlow
  self.use_transactional_tests = false
  setup do
    setup_delivery
    @approval.destroy!
    host! '127.0.0.1:3210'
    @forgery_inherited = !ApplicationController.config.key?(:allow_forgery_protection)
    @forgery = [ActionController::Base.allow_forgery_protection, ApplicationController.allow_forgery_protection]
    ActionController::Base.allow_forgery_protection = ApplicationController.allow_forgery_protection = true
  end
  teardown do
    ActionController::Base.allow_forgery_protection = @forgery.first
    if @forgery_inherited
      ApplicationController.config.delete(:allow_forgery_protection)
    else
      ApplicationController.allow_forgery_protection = @forgery.last
    end
    teardown_delivery
  end

  test 'replacement_pending_cancel_expiry_and_supersession_preserve_old_access' do
    old = email_session
    first = prepare_replacement
    assert valid_email?(old)
    assert_equal @connection.id, GraduateEmailActiveAddress.find_by!(student_id: @student.id).connection_id
    assert_equal first[0].id, GraduateEmail::Enrollment.intent!(token: first[1], browser_token: first[3])
    GraduateEmail::Revocation.approval!(approval: first[0], actor: @actor, impersonating: false)
    assert_nil recovery_redeem(first)
    assert valid_email?(old)
    GraduateEmailLimitEvent.where(kind: 'send_address').update_all(occurred_at: 61.seconds.ago)
    expired = prepare_replacement
    travel_to expired[0].expires_at
    assert_nil recovery_redeem(expired)
    travel_back
    assert valid_email?(old)
    third, = issue_approval(address: 'third@example.com', replacement: true)
    assert expired[0].reload.revoked_at
    assert_equal @connection.id, third.replacement_of_connection_id
    assert valid_email?(old)
  end

  test 'replacement_atomic_switch_preserves_google_budgets_and_notifies_only_old_address' do
    old = email_session
    login = challenge(request_code)
    deliver_row(login)
    login_code = otp_code_for(public_id: login.public_id)
    google = GraduateIdentity.create!(student: @student, linked_by: @actor, provider: 'google_oauth2', uid: 'recovery-google')
    google_token = GraduateSession.issue!(google)
    fail_verify
    data = prepare_replacement
    limits = GraduateEmailLimitEvent.where(kind: %w[send_address verify_address verify_student]).pluck(:id)
    grant = recovery_redeem(data)
    assert_instance_of GraduateEmail::Grant, grant
    assert @connection.reload.revoked_at
    refute valid_email?(old)
    assert_nil redeem(login, code: login_code)
    assert_equal 'revoked', login.reload.state
    assert_equal grant.connection_id, GraduateEmailActiveAddress.find_by!(student_id: @student.id).connection_id
    assert valid_email?(grant.session_token, GraduateEmailConnection.find(grant.connection_id))
    assert GraduateSession.valid_for?(google_token, identity_id: google.id, student_id: @student.id)
    assert_equal limits.sort, GraduateEmailLimitEvent.where(id: limits).pluck(:id).sort
    assert data[0].reload.consumed_at
    assert_nil recovery_redeem(data)
    notice = GraduateEmailNotice.sole
    assert_equal @connection.id, notice.old_connection_id
    assert_equal grant.connection_id, notice.replacement_connection_id
    job = Delayed::Job.where(queue: 'graduate_email_notice').sole
    assert_equal [:@notice_id], job.payload_object.instance_variables
    assert_equal notice.id, job.payload_object.notice_id
    GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
    GraduateAuthenticationMailer.stub(:transport_class, @transport) { Delayed::Worker.new(queues: ['graduate_email_notice']).run(job) }
    message = @mail_messages.last
    assert message.to == [@connection.normalized_address], 'Notice recipient is immutable old address'
    assert_safe_absent(message.encoded, data[0].normalized_address, data[1], data[4], 'http://', 'https://')
    assert_equal 'sent', notice.reload.state
    refute valid_email?(old)
  end

  test 'notice_capacity_and_enqueue_failure_roll_back_complete_transition' do
    token = email_session
    data = prepare_replacement
    fill_notice_queue(50)
    before = [GraduateEmailConnection.count, GraduateSession.count, GraduateEmailAuditEvent.count]
    assert_nil recovery_redeem(data)
    assert_equal before, [GraduateEmailConnection.count, GraduateSession.count, GraduateEmailAuditEvent.count]
    assert_nil data[0].reload.consumed_at
    assert_equal 'sent', data[2].reload.state
    assert valid_email?(token)
    assert_equal 0, GraduateEmailNotice.count
    Delayed::Job.where(queue: 'graduate_email_notice').delete_all
    Delayed::Job.stub(:enqueue, nil) { assert_nil recovery_redeem(data) }
    assert_nil data[0].reload.consumed_at
    assert valid_email?(token)
    assert_equal before, [GraduateEmailConnection.count, GraduateSession.count, GraduateEmailAuditEvent.count]
    assert_equal 0, GraduateEmailNotice.count
    # Saturated OTP and unrelated queues do not consume the notice reserve.
    Delayed::Job.where(queue: 'graduate_email').delete_all
    500.times { Delayed::Job.enqueue(GraduateEmailDeliveryJob.new(SecureRandom.hex(32)), queue: 'graduate_email') }
    sentinel = Delayed::Job.enqueue(GraduateEmailNoticeJob.new(1), queue: 'unrelated')
    assert recovery_redeem(data)
    assert_equal 500, Delayed::Job.where(queue: 'graduate_email').count
    assert Delayed::Job.exists?(sentinel.id)
    assert_equal 1, Delayed::Job.where(queue: 'graduate_email_notice').count
  end

  test 'same_address_requires_explicit_recovery_and_wrong_student_address_never_mutates' do
    other = create(:student)
    foreign = GraduateEmailConnection.create!(student: other, approved_by: @actor, normalized_address: 'foreign@example.com', verified_at: Time.current)
    mapping = GraduateEmailActiveAddress.create!(student: other, connection: foreign, normalized_address: foreign.normalized_address)
    before = [@mapping.attributes, mapping.attributes]
    assert_raises(GraduateAuthentication::Rejected) { issue_approval(address: foreign.normalized_address, replacement: true) }
    assert_equal before, [@mapping.reload.attributes, mapping.reload.attributes]
    assert_raises(GraduateAuthentication::Rejected) { issue_approval }
    data = prepare_replacement(address: @connection.normalized_address)
    assert recovery_redeem(data)
    assert @connection.reload.revoked_at
    assert_equal 2, GraduateEmailActiveAddress.count
  end

  test 'confirmed_route_scoped_revocation_ignores_forged_body_ids_and_works_disabled' do
    data = prepare_replacement
    old = email_session
    login = challenge(request_code)
    deliver_row(login)
    code = otp_code_for(public_id: login.public_id)
    google = GraduateIdentity.create!(student: @student, linked_by: @actor, provider: 'google_oauth2', uid: 'revoke-google')
    gt = GraduateSession.issue!(google)
    other = create(:student)
    ppy_login(@actor)
    path = "/students/#{@student.id}/graduate-email-connections/#{@connection.id}"
    get staff_student_graduate_connections_path(@student)
    delete path, params: {confirmation: '1'}
    assert_response :unprocessable_entity
    get staff_student_graduate_connections_path(@student)
    delete path, params: {authenticity_token: csrf_token}
    assert_nil @connection.reload.revoked_at
    get staff_student_graduate_connections_path(other)
    delete "/students/#{other.id}/graduate-email-connections/#{@connection.id}", params: {confirmation: '1', authenticity_token: csrf_token}
    assert_nil @connection.reload.revoked_at
    GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
    get staff_student_graduate_connections_path(@student)
    delete path, params: {student_id: other.id, id: 999999, connection_id: 999999, confirmation: '1', authenticity_token: csrf_token}
    assert @connection.reload.revoked_at
    assert data[0].reload.revoked_at
    assert_nil data[0].consumed_at
    assert_equal 0, GraduateEmailActiveAddress.where(student_id: @student.id).count
    assert_equal 'revoked', login.reload.state
    GraduateEmail::Control.set_enabled!(enabled: true, actor_id: @actor.id)
    refute valid_email?(old)
    assert_nil redeem(login, code: code)
    assert_nil recovery_redeem(data)
    assert GraduateSession.valid_for?(gt, identity_id: google.id, student_id: @student.id)
  end

  test 'recovery_actor_student_identity_and_https_boundaries' do
    [false, nil, '1'].each do |verified|
      assert_raises(GraduateAuthentication::Rejected) { issue_approval(replacement: true, identity_verified: verified) }
    end
    assert_raises(GraduateAuthentication::Rejected) { issue_approval(replacement: true, impersonating: true) }
    @actor.update!(role: User::STAFF)
    assert_raises(GraduateAuthentication::Rejected) { issue_approval(replacement: true) }
    assert_raises(GraduateAuthentication::Rejected) { GraduateEmail::Revocation.connection!(connection: @connection, actor: @actor, impersonating: false) }
    @actor.update!(role: User::MANAGER)
    data = prepare_replacement
    @actor.update!(blocked: true)
    assert_nil recovery_redeem(data)
    assert_nil data[0].reload.consumed_at
    @actor.update!(blocked: false)
    ppy_login(@actor)
    get staff_student_graduate_connections_path(@student)
    token = csrf_token
    Rails.env.stub(:production?, true) do
      delete "/students/#{@student.id}/graduate-email-connections/#{@connection.id}", params: {authenticity_token: token, confirmation: '1'}
      assert_response :bad_request
    end
    assert_nil @connection.reload.revoked_at
    assert_includes response.headers['Cache-Control'], 'no-store'
  end
  test 'email_owner_current_historical_download_and_contact_boundaries' do
    own = create(:thesis, student: @student)
    foreign_student = create(:student)
    foreign = create(:thesis, student: foreign_student)
    documents = [own, foreign].map do |thesis|
      create(:document, thesis: thesis, user: thesis.student, supplemental: false,
        file: Rack::Test::UploadedFile.new('test/fixtures/files/pdf-document.pdf', 'application/pdf'))
    end
    versions = [own, foreign].map { |thesis| thesis.create_submission_snapshot!(thesis.student) }
    get '/graduate/email'
    post '/graduate/email/challenges', params: {address: @connection.normalized_address, authenticity_token: csrf_token}
    row = GraduateEmailChallenge.where(state: 'queued').sole
    deliver_row(row)
    code = otp_code_for(public_id: row.public_id)
    post '/graduate/email/verify', params: {code: code, authenticity_token: csrf_token}
    assert_redirected_to student_view_index_path
    assert_equal 'graduate_email', session[:auth_source]
    get download_student_thesis_document_path(@student, own, documents[0])
    assert_response :success
    assert response.body.b == File.binread(documents[0].file.path), 'Owner current bytes'
    get download_student_thesis_document_path(foreign_student, foreign, documents[1])
    assert_redirected_to unauthorized_path
    versions.each do |version|
      doc = version.submission_documents.first
      get student_thesis_submission_version_submission_document_path(version.thesis.student, version.thesis, version, doc)
      assert_redirected_to unauthorized_path
    end
    get documents[0].file_url
    assert_response :not_found
    get graduate_connections_path
    assert_select 'input[name=address]', count: 0
    assert_select 'form[action*="graduate-email-connections"]', count: 0
    get graduate_login_path
    post organize_student_information_student_thesis_path(@student, own), params: {authenticity_token: csrf_token,
      student: {name: @student.name, first_name: @student.first_name, email_external: 'contact-only@example.com'}}
    assert_redirected_to student_view_thesis_process_path(own, Thesis::PROCESS_UPDATE)
    assert_equal 'approved@example.com', @mapping.reload.normalized_address
    assert_equal 'contact-only@example.com', @student.reload.email_external
    [Thesis::ACCEPTED, Thesis::PUBLISHED].each do |state|
      own.update!(status: state)
      get edit_student_thesis_document_path(@student, own, documents[0])
      assert_redirected_to unauthorized_path
      get download_student_thesis_document_path(@student, own, documents[0])
      assert_response :success
      get graduate_login_path
      post organize_student_information_student_thesis_path(@student, own), params: {authenticity_token: csrf_token, student: {name: 'Denied'}}
      assert_redirected_to unauthorized_path
    end
    get graduate_login_path
    post organize_student_information_student_thesis_path(foreign_student, foreign), params: {authenticity_token: csrf_token, student: {name: 'Denied'}}
    assert_redirected_to unauthorized_path
    assert_raises(ActiveRecord::RecordNotFound) { get download_student_thesis_document_path(@student, foreign, documents[1]) }
  ensure
    documents&.each { |doc| FileUtils.rm_rf(File.dirname(doc.file.path)) }
    versions&.each { |version| version.submission_documents.each { |doc| FileUtils.rm_rf(File.dirname(doc.file.path)) } }
  end

  test 'staff_notice_state_and_failed_notice_never_restore_access' do
    data = prepare_replacement
    assert recovery_redeem(data)
    notice = GraduateEmailNotice.sole
    ppy_login(@actor)
    get staff_student_graduate_connections_path(@student)
    assert_select '[data-email-notice-state]', text: /Queued/
    assert_select '[data-email-approval-actor]'
    failing = Class.new do
      def initialize(*); end
      def deliver!(*); raise IOError, 'RAM failure'; end
    end
    GraduateAuthenticationMailer.stub(:transport_class, failing) { GraduateEmailNoticeJob.new(notice.id).perform }
    assert_equal 'failed', notice.reload.state
    assert @connection.reload.revoked_at
    assert_equal notice.replacement_connection_id, GraduateEmailActiveAddress.find_by!(student_id: @student.id).connection_id
    get staff_student_graduate_connections_path(@student)
    assert_select '[data-email-notice-state]', text: /Failed/
    notice.update_columns(state: 'claimed')
    get staff_student_graduate_connections_path(@student)
    assert_select '[data-email-notice-state]', text: /Unknown/
    assert_safe_absent(response.body, data[1], data[4], data[0].token_digest)
  end

  test 'connection_http_denials_are_private_and_body_ids_never_choose_owner' do
    ppy_login(@actor)
    get staff_student_graduate_connections_path(@student)
    path = "/students/#{@student.id}/graduate-email-connections/#{@connection.id}"
    delete path, params: {confirmation: '1'}
    assert_response :unprocessable_entity
    assert_includes response.headers['Cache-Control'].to_s, 'no-store'
    assert_equal 'no-referrer', response.headers['Referrer-Policy']
    other = create(:student)
    get staff_student_graduate_connections_path(@student)
    post review_student_graduate_email_invitations_path(@student), params: {student_id: other.id,
      address: 'route-owner@example.com', confirmed_address: 'route-owner@example.com', replacement: '1', authenticity_token: csrf_token}
    assert_response :success
    post student_graduate_email_invitations_path(@student), params: {student_id: other.id, reviewed_address: 'route-owner@example.com',
      identity_verified: '1', address_confirmed: '1', replacement: '1', authenticity_token: csrf_token}
    assert_response :success
    assert_equal @student.id, GraduateEmailApproval.order(:id).last.student_id
    [User::STAFF, User::MANAGER].each do |role|
      fresh_browser
      @actor.update!(role: role)
      ppy_login(@actor)
      get login_as_student_path(@student) if role == User::MANAGER
      get graduate_login_path
      delete path, params: {confirmation: '1', authenticity_token: csrf_token}
      assert_redirected_to unauthorized_path
      assert_nil @connection.reload.revoked_at
    end
    fresh_browser
    ppy_login(@student)
    get graduate_login_path
    delete path, params: {confirmation: '1', authenticity_token: csrf_token}
    assert_redirected_to unauthorized_path
    assert_nil @connection.reload.revoked_at
  end

  test 'historical_notice_recipient_and_owner_are_immutable' do
    data = prepare_replacement
    assert recovery_redeem(data)
    old = @connection.reload
    original = old.attributes.slice('student_id', 'approved_by_id', 'normalized_address', 'verified_at')
    other = create(:student)
    old.update!(student_id: other.id, normalized_address: 'redirected@example.com')
    assert_equal original, old.reload.attributes.slice(*original.keys)
    notice = GraduateEmailNotice.sole
    GraduateAuthenticationMailer.stub(:transport_class, @transport) { GraduateEmailNoticeJob.new(notice.id).perform }
    assert @mail_messages.last.to == ['approved@example.com'], 'Historical recipient cannot be reassigned'
  end

end

require_relative '../support/graduate_email_delivery_process_helpers'

class GraduateEmailNoticeCrashTest < ActionDispatch::IntegrationTest
  include GraduateEmailRecoveryHelpers
  self.use_transactional_tests = false
  setup do
    setup_delivery
    @approval.destroy!
  end
  teardown { teardown_delivery }

  test 'abandoned_notice_claim_before_smtp_and_after_acceptance_never_sends_twice' do
    %w[after_claim after_acceptance].each do |barrier|
      data = prepare_replacement(address: "#{barrier}@example.com")
      assert recovery_redeem(data)
      notice = GraduateEmailNotice.order(:id).last
      input, output, waiter = nil
      parent_socket, child_socket = UNIXSocket.pair
      input, output, waiter = Open3.popen2e(RbConfig.ruby, '-S', 'bundle', 'exec', 'rails', 'runner',
        'test/support/graduate_email_notice_worker.rb', 3 => child_socket)
      child_socket.close
      marker = -> do
        Timeout.timeout(30) do
          loop do
            line = output.gets
            raise 'Notice worker ended' unless line
            break line.strip if line.start_with?('DELIVERY_')
          end
        end
      end
      input.puts JSON.generate(database: ActiveRecord::Base.connection_db_config.configuration_hash.slice(:adapter, :database), barrier: barrier, limit: 1)
      input.flush
      assert_equal 'DELIVERY_READY', marker.call
      input.puts 'START'; input.flush
      if barrier == 'after_acceptance'
        encoded = Timeout.timeout(30) { Marshal.load(parent_socket) }
        message = Mail.read_from_string(encoded)
        assert message.to == [GraduateEmailConnection.find(notice.old_connection_id).normalized_address], 'Old address only'
        parent_socket.puts 'ACCEPT'; parent_socket.flush
        assert_equal 'DELIVERY_NETWORK', marker.call
      end
      assert_equal "DELIVERY_BARRIER #{barrier}", marker.call
      assert_equal 'claimed', notice.reload.state
      Process.kill('KILL', waiter.pid)
      assert Timeout.timeout(10) { waiter.value.signaled? }, 'Persisted notice worker was killed'
      Delayed::Job.where(queue: 'graduate_email_notice').update_all(locked_at: nil, locked_by: nil)
      Delayed::Job.enqueue(GraduateEmailNoticeJob.new(notice.id), queue: 'graduate_email_notice')
      count = @mail_messages.size
      GraduateAuthenticationMailer.stub(:transport_class, @transport) do
        Delayed::Worker.new(queues: ['graduate_email_notice']).work_off(10)
      end
      assert_equal count, @mail_messages.size
      assert_equal 'claimed', notice.reload.state
      assert GraduateEmailConnection.find(notice.old_connection_id).revoked_at
      @connection = GraduateEmailConnection.find(notice.replacement_connection_id)
    ensure
      if waiter&.alive?
        Process.kill('KILL', waiter.pid) rescue Errno::ESRCH
        waiter.join(5)
      end
      [input, output, parent_socket, child_socket].compact.each { |io| io.close unless io.closed? }
    end
  end
end
