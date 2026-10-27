# frozen_string_literal: true
require 'test_helper'
require_relative '../support/graduate_email_flow_helpers'
require_relative '../support/graduate_oauth_flow'

# C01-C09: one usable claim per canonical address across students. Failure
# scenarios are recorded in opus-pending-collision-staff-confirmation-r1-report.
class GraduateEmailCollisionTest < ActionDispatch::IntegrationTest
  include GraduateEmailFlowHelpers
  include GraduateOAuthFlow
  self.use_transactional_tests = false

  setup do
    setup_flow
    host! '127.0.0.1:3210'
    @forgery = [ActionController::Base.allow_forgery_protection, ApplicationController.allow_forgery_protection]
    @app_forgery_inherited = !ApplicationController.config.key?(:allow_forgery_protection)
    ActionController::Base.allow_forgery_protection = ApplicationController.allow_forgery_protection = true
    @owner = create(:student)
    @other = create(:student)
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery.first
    if @app_forgery_inherited
      ApplicationController.config.delete(:allow_forgery_protection)
    else
      ApplicationController.allow_forgery_protection = @forgery.last
    end
    teardown_delivery
  end

  test 'cross_student_pending_and_active_addresses_refuse_with_specific_reasons' do
    reserved, = issue_for(@owner, 'shared@example.com')
    connect(create(:student), 'active@example.com')
    connect(@other, 'other-old@example.com')
    before = durable_state
    {
      ['  SHARED@Example.com ', 'shared@EXAMPLE.COM'] => :pending_elsewhere,
      ["\tActive@Example.COM", 'active@example.com'] => :active_elsewhere
    }.each do |(address, confirmation), reason|
      [false, true].each do |replacement|
        error = assert_raises(GraduateEmail::Enrollment::Refused) do
          GraduateEmail::Enrollment.issue!(student: @other, actor: @actor, address: address, confirmed_address: confirmation,
            identity_verified: true, impersonating: false, replacement: replacement)
        end
        assert_equal reason, error.reason, "#{reason} replacement=#{replacement}"
        assert_kind_of GraduateAuthentication::Rejected, error
        assert_equal before, durable_state, 'A refused claim changes nothing'
      end
    end
    assert_nil reserved.reload.revoked_at
    {
      ['one@example.com,two@example.com', 'one@example.com,two@example.com'] => :unsupported,
      ['Name <one@example.com>', 'one@example.com'] => :unsupported,
      ['one@example.com', 'two@example.com'] => :mismatch,
      ['one@example.com', 'not an address'] => :mismatch
    }.each do |(address, confirmation), reason|
      error = assert_raises(GraduateEmail::Enrollment::Refused) do
        GraduateEmail::Enrollment.issue!(student: @other, actor: @actor, address: address, confirmed_address: confirmation,
          identity_verified: true, impersonating: false, replacement: true)
      end
      assert_equal reason, error.reason
    end
    error = assert_raises(GraduateEmail::Enrollment::Refused) { issue_for(@other, 'fresh@example.com') }
    assert_equal :state_changed, error.reason, 'Initial issue for a connected student'
    error = assert_raises(GraduateEmail::Enrollment::Refused) { issue_for(create(:student), 'fresh@example.com', replacement: true) }
    assert_equal :state_changed, error.reason, 'Replacement without a current connection'
    GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
    error = assert_raises(GraduateEmail::Enrollment::Refused) { issue_for(create(:student), 'fresh@example.com') }
    assert_equal :unavailable, error.reason
  end

  test 'same_student_supersedes_own_claim_and_replacement_keeps_old_access' do
    first, = issue_for(@owner, 'mine@example.com')
    second, = issue_for(@owner, ' MINE@example.com')
    assert first.reload.revoked_at, 'Own earlier invitation superseded'
    assert_nil second.reload.revoked_at
    third, = issue_for(@owner, 'other-mine@example.com')
    assert second.reload.revoked_at
    connection = connect(@other, 'other-old@example.com')
    recovery, = issue_for(@other, 'other-old@example.com', replacement: true)
    replacement, = issue_for(@other, 'other-new@example.com', replacement: true)
    assert recovery.reload.revoked_at
    assert_equal connection.id, replacement.replacement_of_connection_id
    assert_nil connection.reload.revoked_at
    assert_equal 'other-old@example.com', GraduateEmailActiveAddress.find_by!(student_id: @other.id).normalized_address
    assert_nil third.reload.revoked_at
  end

  # D1: only irreversible events release a reservation; reversible approver or
  # student status never revives a competing claim.
  test 'reservation_releases_only_on_irreversible_lifecycle_events' do
    expectations = {
      cancel: nil, before_expiry: :pending_elsewhere, expire: nil, supersede: nil, owner_block: nil, generation: nil, revoke_after_consume: nil,
      consumed: :active_elsewhere, approver_demoted: :pending_elsewhere, approver_blocked: :pending_elsewhere,
      untouched: :pending_elsewhere
    }
    expectations.each do |event, expected|
      reset_rows
      owner = create(:student)
      claimant = create(:student)
      approver = create(:user, role: User::MANAGER)
      approval, = issue_for(owner, 'contested@example.com', actor: approver)
      case event
      when :cancel then GraduateEmail::Revocation.approval!(approval: approval, actor: @actor, impersonating: false)
      # travel_to drops sub-second precision; check both sides of the boundary.
      when :before_expiry then travel_to approval.expires_at - 1.second
      when :expire then travel_to approval.expires_at + 1.second
      when :supersede then issue_for(owner, 'elsewhere@example.com', actor: approver)
      when :owner_block then owner.block
      when :generation
        GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
        GraduateEmail::Control.set_enabled!(enabled: true, actor_id: @actor.id)
      when :consumed, :revoke_after_consume
        consume(approval)
        if event == :revoke_after_consume
          GraduateEmail::Revocation.connection!(connection: GraduateEmailConnection.find_by!(student_id: owner.id),
            actor: @actor, impersonating: false)
        end
      when :approver_demoted then approver.update!(role: User::STAFF)
      when :approver_blocked then approver.block
      end
      if expected
        error = assert_raises(GraduateEmail::Enrollment::Refused, event.to_s) { issue_for(claimant, 'Contested@Example.com') }
        assert_equal expected, error.reason, event.to_s
        assert_equal 0, GraduateEmailApproval.where(student_id: claimant.id).count, event.to_s
      else
        claim, = issue_for(claimant, 'Contested@Example.com')
        assert_equal 'contested@example.com', claim.normalized_address, event.to_s
      end
      travel_back
    end
  end

  # D3: duplicates created before this change can never silently pick a student.
  test 'preexisting_duplicate_pending_fails_closed_until_one_is_canceled' do
    owner_approval, owner_token = issue_for(@owner, 'legacy@example.com')
    owner_browser = SecureRandom.hex(32)
    queued = challenge(GraduateEmail::Challenges.request!(purpose: :enroll, browser_token: owner_browser, ip: @ip, approval_id: owner_approval.id))
    sent_browser = SecureRandom.hex(32)
    GraduateEmailLimitEvent.where(kind: 'send_address').delete_all
    sent = challenge(GraduateEmail::Challenges.request!(purpose: :enroll, browser_token: sent_browser, ip: '192.0.2.9', approval_id: owner_approval.id))
    deliver_row(sent)
    sent_code = otp_code_for(public_id: sent.public_id)
    assert sent_code.is_a?(String), 'Code sent before the duplicate existed'
    @mail_messages.clear
    duplicate, duplicate_token = legacy_duplicate(@other, 'legacy@example.com')
    [[owner_approval, owner_token], [duplicate, duplicate_token]].each do |approval, token|
      assert_raises(GraduateAuthentication::Rejected) do
        GraduateEmail::Enrollment.intent!(token: token, browser_token: SecureRandom.hex(32))
      end
      GraduateEmailLimitEvent.where(kind: 'send_address').delete_all
      result = GraduateEmail::Challenges.request!(purpose: :enroll, browser_token: SecureRandom.hex(32), ip: @ip, approval_id: approval.id)
      assert_equal 'noop', challenge(result).purpose, 'A blocked claim never sends'
    end
    deliver_row(queued)
    assert_empty @mail_messages, 'Queued code is not sent while the address is contested'
    refute_equal 'sent', queued.reload.state
    assert_nil redeem(sent, browser: sent_browser, code: sent_code)
    assert_equal 0, GraduateEmailActiveAddress.count
    assert_equal 0, GraduateSession.count
    assert_nil owner_approval.reload.consumed_at
    assert_nil duplicate.reload.consumed_at
    valid_shape = public_invitation_shape(issue_for(create(:student), 'unrelated@example.com').last)
    assert_equal valid_shape, public_invitation_shape(duplicate_token), 'Blocked invitation stays generic'
    assert_equal 0, GraduateEmailChallenge.where(approval_id: duplicate.id).count
    fresh_browser
    ppy_login(@actor)
    get staff_student_graduate_connections_path(@owner)
    assert_select '[data-email-approval-blocked]', count: 1
    assert_includes response.body, 'Pending, blocked'
    refute_includes response.body, @other.name
    GraduateEmail::Revocation.approval!(approval: duplicate, actor: @actor, impersonating: false)
    get staff_student_graduate_connections_path(@owner)
    assert_select '[data-email-approval-blocked]', count: 0
    grant = redeem(sent, browser: sent_browser, code: sent_code)
    assert_instance_of GraduateEmail::Grant, grant
    assert_equal @owner.id, GraduateEmailActiveAddress.find_by!(normalized_address: 'legacy@example.com').student_id
  end

  private

  def issue_for(student, address, actor: @actor, **options)
    GraduateEmail::Enrollment.issue!(student: student, actor: actor, address: address, confirmed_address: address,
      identity_verified: true, impersonating: false, **options)
  end

  def connect(student, address)
    connection = GraduateEmailConnection.create!(student: student, approved_by: @actor, normalized_address: address, verified_at: Time.current)
    GraduateEmailActiveAddress.create!(student: student, connection: connection, normalized_address: address)
    connection
  end

  def legacy_duplicate(student, address)
    token = SecureRandom.urlsafe_base64(32)
    approval = GraduateEmailApproval.create!(student: student, approved_by: @actor, normalized_address: address,
      token_digest: Digest::SHA256.hexdigest(token), generation: 1, expires_at: 48.hours.from_now)
    [approval, token]
  end

  def consume(approval)
    browser = SecureRandom.hex(32)
    GraduateEmailLimitEvent.where(kind: 'send_address').delete_all
    row = challenge(GraduateEmail::Challenges.request!(purpose: :enroll, browser_token: browser, ip: @ip, approval_id: approval.id))
    deliver_row(row)
    assert_instance_of GraduateEmail::Grant, redeem(row, browser: browser, code: otp_code_for(public_id: row.public_id))
  end

  def public_invitation_shape(token)
    fresh_browser
    host! '127.0.0.1:3210'
    get '/graduate/email/enroll', params: {token: token}
    assert_redirected_to graduate_email_verify_path
    follow_redirect!
    first = [response.status, shape]
    post '/graduate/email/resend', params: {authenticity_token: csrf_token}
    [first, [response.status, shape]]
  end

  def shape
    doc = Nokogiri::HTML(response.body)
    [doc.css('h1').map { |item| item.text.strip }, doc.css('main p').map { |item| item.text.strip },
      doc.css('main button, main input[type="submit"]').map { |item| item.name == 'button' ? item.text.strip : item['value'] },
      doc.css('main a').map { |link| [link.text.strip, link['href']] }]
  end

  def durable_state
    [GraduateEmailApproval.order(:id).map(&:attributes), GraduateEmailActiveAddress.order(:id).map(&:attributes),
      GraduateEmailConnection.order(:id).map(&:attributes), GraduateEmailChallenge.count, GraduateEmailAuditEvent.count]
  end

  def reset_rows
    travel_back
    GraduateEmailChallenge.delete_all
    Delayed::Job.delete_all
    GraduateSession.delete_all
    GraduateEmailActiveAddress.delete_all
    GraduateEmailApproval.delete_all
    GraduateEmailConnection.delete_all
    GraduateEmailLimitEvent.delete_all
    GraduateEmailCooldown.delete_all
    GraduateEmailControl.find(1).update!(enabled: true, generation: 1)
  end
end

# C10-C16: staff-only review of the server-normalized address before issuing.
class GraduateEmailStaffReviewTest < ActionDispatch::IntegrationTest
  include GraduateEmailFlowHelpers
  include GraduateOAuthFlow
  self.use_transactional_tests = false

  setup do
    setup_flow
    host! '127.0.0.1:3210'
    @forgery = [ActionController::Base.allow_forgery_protection, ApplicationController.allow_forgery_protection]
    @app_forgery_inherited = !ApplicationController.config.key?(:allow_forgery_protection)
    ActionController::Base.allow_forgery_protection = ApplicationController.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery.first
    if @app_forgery_inherited
      ApplicationController.config.delete(:allow_forgery_protection)
    else
      ApplicationController.allow_forgery_protection = @forgery.last
    end
    teardown_delivery
  end

  test 'review_shows_server_canonical_address_and_creates_nothing' do
    ppy_login(@actor)
    before = counts
    review(address: "  Mixed.Case+Tag@Example.COM\t", confirmed: 'mixed.case+tag@EXAMPLE.com')
    assert_response :success
    assert_equal 'no-store', response.headers['Cache-Control']
    # Forms on this page must keep a real Origin for Rails' origin check.
    assert_equal 'same-origin', response.headers['Referrer-Policy']
    assert_confirmation_page('mixed.case+tag@example.com', replacement: false)
    assert_equal before, counts, 'Review creates no approval, challenge, job or audit'
    enrolled_connection
    review(address: 'New@Example.com', confirmed: 'new@example.COM', replacement: true)
    assert_response :success
    assert_confirmation_page('new@example.com', replacement: true)
    assert_includes main_text, 'The current address stays usable until the new mailbox is verified.'
    assert_equal before, counts
    assert_equal '[FILTERED]', request.filtered_parameters['address']
    assert_equal '[FILTERED]', request.filtered_parameters['confirmed_address']
  end

  test 'review_and_create_errors_are_specific_staff_only_and_create_nothing' do
    other = create(:student, email_external: 'family@example.org')
    issue_approval(student: other, address: 'pending@example.com')
    active_owner = create(:student)
    connection = GraduateEmailConnection.create!(student: active_owner, approved_by: @actor, normalized_address: 'active@example.com', verified_at: Time.current)
    GraduateEmailActiveAddress.create!(student: active_owner, connection: connection, normalized_address: 'active@example.com')
    ppy_login(@actor)
    before = counts
    approvals = GraduateEmailApproval.order(:id).map(&:attributes)
    cases = [
      ['one@example.com, two@example.com', 'one@example.com, two@example.com', false, 'unsupported', :unprocessable_entity, nil],
      ['one@example.com', 'two@example.com', false, 'mismatch', :unprocessable_entity, nil],
      ['ACTIVE@example.com', 'active@example.com', false, 'active_elsewhere', :conflict, active_owner],
      [' pending@example.com', 'PENDING@example.com', false, 'pending_elsewhere', :conflict, other],
      ['fresh@example.com', 'fresh@example.com', true, 'state_changed', :unprocessable_entity, nil]
    ]
    messages = cases.map do |address, confirmed, replacement, reason, status, owner|
      review(address: address, confirmed: confirmed, replacement: replacement)
      assert_response status
      doc = Nokogiri::HTML(response.body)
      alert = doc.at_css('[role="alert"][data-review-error]')
      assert alert, reason
      assert_equal reason, alert['data-review-error']
      assert_nil doc.at_css('input[name="reviewed_address"]'), "#{reason} offers no create form"
      assert doc.at_css("form[action='#{review_student_graduate_email_invitations_path(@student)}'] input[name='address']"), "#{reason} re-entry"
      assert_nil doc.at_css('input[name="address"]')['value'], 'Re-entry starts empty'
      links = doc.css('a[data-conflict-record]').map { |link| link['href'] }
      assert_equal(owner ? [staff_student_graduate_connections_path(owner)] : [], links, reason)
      [other, active_owner].each do |student|
        [student.name, student.sisid, student.email, student.email_external].compact.each do |detail|
          refute_includes response.body, detail, "#{reason} exposes no other student detail"
        end
      end
      post student_graduate_email_invitations_path(@student), params: create_params('one@example.com')
      assert_equal 'stale', Nokogiri::HTML(response.body).at_css('[data-review-error]')['data-review-error'], "#{reason} stores no review"
      alert.text.strip
    end
    assert_equal messages.size, messages.uniq.size, 'Each reason has its own message'
    assert_includes messages[2], 'another student record'
    assert_includes messages[3], 'another student record'
    assert_equal before, counts
    assert_equal approvals, GraduateEmailApproval.order(:id).map(&:attributes)
    GraduateEmail::Enrollment.stub(:review, ->(**) { raise ActiveRecord::StatementInvalid, 'SQLSTATE RAW_DB_SENTINEL' }) do
      review(address: 'fine@example.com', confirmed: 'fine@example.com')
    end
    assert_response :unprocessable_entity
    assert_equal 'unavailable', Nokogiri::HTML(response.body).at_css('[data-review-error]')['data-review-error']
    refute_includes response.body, 'RAW_DB_SENTINEL'
    review(address: 'fine@example.com', confirmed: 'fine@example.com')
    GraduateEmail::Enrollment.stub(:issue!, ->(**) { raise ActiveRecord::StatementInvalid, 'SQLSTATE RAW_DB_SENTINEL' }) do
      post student_graduate_email_invitations_path(@student), params: create_params('fine@example.com')
    end
    assert_equal 'unavailable', Nokogiri::HTML(response.body).at_css('[data-review-error]')['data-review-error']
    refute_includes response.body, 'RAW_DB_SENTINEL'
    GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
    review(address: 'fine@example.com', confirmed: 'fine@example.com')
    assert_equal 'unavailable', Nokogiri::HTML(response.body).at_css('[data-review-error]')['data-review-error']
    assert_equal approvals, GraduateEmailApproval.order(:id).map(&:attributes)
  end

  test 'create_requires_current_matching_review' do
    other = create(:student)
    ppy_login(@actor)
    get staff_student_graduate_connections_path(@student)
    post student_graduate_email_invitations_path(@student), params: create_params('approved@example.com')
    assert_stale
    {
      tampered: -> { post student_graduate_email_invitations_path(@student), params: create_params('attacker@example.com') },
      other_student: -> { post student_graduate_email_invitations_path(other), params: create_params('approved@example.com') },
      mode_flip: -> { post student_graduate_email_invitations_path(@student), params: create_params('approved@example.com', replacement: '1') },
      expired: -> { travel 16.minutes; post student_graduate_email_invitations_path(@student), params: create_params('approved@example.com') },
      revisited: -> { get staff_student_graduate_connections_path(@student); post student_graduate_email_invitations_path(@student), params: create_params('approved@example.com') },
      canceled: -> {
        destination = Nokogiri::HTML(response.body).css('a[data-review-exit]').find { |link| link.text.strip == 'Cancel' }['href']
        get destination
        post student_graduate_email_invitations_path(@student), params: create_params('approved@example.com')
      }
    }.each do |name, attempt|
      review(address: 'Approved@Example.com', confirmed: 'approved@example.com')
      assert_response :success
      attempt.call
      assert_stale(name)
      travel_back
      post student_graduate_email_invitations_path(@student), params: create_params('approved@example.com')
      assert_stale("#{name} consumed")
    end
    review(address: 'Approved@Example.com', confirmed: 'approved@example.com')
    [{identity_verified: nil}, {address_confirmed: nil}, {identity_verified: '0', address_confirmed: '0'}].each do |missing|
      post student_graduate_email_invitations_path(@student), params: create_params('approved@example.com').merge(missing).compact
      assert_response :unprocessable_entity
      assert_equal 'confirmation', Nokogiri::HTML(response.body).at_css('[data-review-error]')['data-review-error']
      assert_confirmation_page('approved@example.com', replacement: false)
    end
    assert_equal 0, GraduateEmailApproval.count
    post student_graduate_email_invitations_path(@student), params: create_params('approved@example.com')
    assert_response :success
    assert_equal 'no-store', response.headers['Cache-Control']
    assert_equal 'no-referrer', response.headers['Referrer-Policy']
    assert_equal '[FILTERED]', request.filtered_parameters['reviewed_address']
    doc = Nokogiri::HTML(response.body)
    assert_equal ['Share this invitation once'], doc.css('h1').map { |item| item.text.strip }
    assert_equal 'approved@example.com', doc.at_css('[data-approved-address]').text.strip
    approval = GraduateEmailApproval.sole
    assert_equal ['approved@example.com', @student.id, @actor.id, nil], [approval.normalized_address, approval.student_id, approval.approved_by_id, approval.replacement_of_connection_id]
    link = doc.at_css('a[rel="noreferrer"][href*="/graduate/email/enroll?token="]')
    assert link, 'Invitation shown once with no referrer'
    token = Rack::Utils.parse_query(URI.parse(link['href']).query).fetch('token')
    assert_equal Digest::SHA256.hexdigest(token), approval.token_digest
    assert_empty flash.to_hash
    post student_graduate_email_invitations_path(@student), params: create_params('approved@example.com')
    assert_stale('replay')
    refute_includes response.body, token
    get staff_student_graduate_connections_path(@student)
    refute_includes response.body, token
    assert_equal 1, GraduateEmailApproval.count
    review(address: 'race@example.com', confirmed: 'race@example.com')
    issue_approval(student: other, address: 'race@example.com')
    post student_graduate_email_invitations_path(@student), params: create_params('race@example.com')
    assert_response :conflict
    assert_equal 'pending_elsewhere', Nokogiri::HTML(response.body).at_css('[data-review-error]')['data-review-error']
    assert_equal 0, GraduateEmailApproval.where(student_id: @student.id, normalized_address: 'race@example.com').count
    assert_nil approval.reload.revoked_at, 'A refused create supersedes nothing'
  end

  test 'replacement_review_creates_replacement_and_keeps_old_access' do
    enrolled_connection
    ppy_login(@actor)
    review(address: ' Recovery@Example.com', confirmed: 'recovery@example.com', replacement: true)
    post student_graduate_email_invitations_path(@student), params: create_params('recovery@example.com')
    assert_stale('replacement mode must be posted')
    review(address: ' Recovery@Example.com', confirmed: 'recovery@example.com', replacement: true)
    post student_graduate_email_invitations_path(@student), params: create_params('recovery@example.com', replacement: '1')
    assert_response :success
    assert_equal 'recovery@example.com', Nokogiri::HTML(response.body).at_css('[data-approved-address]').text.strip
    assert_equal @connection.id, GraduateEmailApproval.sole.replacement_of_connection_id
    assert_nil @connection.reload.revoked_at
    assert_equal 'approved@example.com', @mapping.reload.normalized_address
  end

  test 'review_and_create_are_denied_outside_authorized_staff' do
    [:staff_role, :blocked_manager, :impersonating, :student].each do |kind|
      fresh_browser
      @actor.update!(role: User::MANAGER, blocked: false)
      case kind
      when :staff_role then @actor.update!(role: User::STAFF); ppy_login(@actor)
      when :blocked_manager then ppy_login(@actor); @actor.update!(blocked: true)
      when :impersonating then ppy_login(@actor); get login_as_student_path(@student)
      when :student then ppy_login(@student)
      end
      get graduate_login_path
      token = csrf_token
      post review_student_graduate_email_invitations_path(@student), params: {address: 'denied@example.com',
        confirmed_address: 'denied@example.com', authenticity_token: token}
      assert_response :redirect, kind.to_s
      refute_includes response.body, 'denied@example.com'
      post student_graduate_email_invitations_path(@student), params: {reviewed_address: 'denied@example.com',
        identity_verified: '1', address_confirmed: '1', authenticity_token: token}
      assert_response :redirect, kind.to_s
      assert_nil session['graduate_email_review'], kind.to_s
      assert_equal 0, GraduateEmailApproval.count, kind.to_s
    end
    @actor.update!(role: User::MANAGER, blocked: false)
    fresh_browser
    ppy_login(@actor)
    get staff_student_graduate_connections_path(@student)
    token = csrf_token
    Rails.env.stub(:production?, true) do
      post review_student_graduate_email_invitations_path(@student), params: {address: 'approved@example.com',
        confirmed_address: 'approved@example.com', authenticity_token: token}
      assert_response :bad_request
    end
    post review_student_graduate_email_invitations_path(@student), params: {address: 'approved@example.com', confirmed_address: 'approved@example.com'}
    assert_response :unprocessable_entity
    assert_equal 0, GraduateEmailApproval.count
  end

  private

  def review(address:, confirmed: address, replacement: false, student: @student)
    get staff_student_graduate_connections_path(student)
    params = {address: address, confirmed_address: confirmed, authenticity_token: csrf_token}
    params[:replacement] = '1' if replacement
    post review_student_graduate_email_invitations_path(student), params: params
  end

  def create_params(address, replacement: nil)
    {reviewed_address: address, identity_verified: '1', address_confirmed: '1', replacement: replacement,
      authenticity_token: csrf_token}.compact
  end

  def assert_confirmation_page(address, replacement:)
    doc = Nokogiri::HTML(response.body)
    assert_equal ['Review email sign-in address'], doc.css('h1').map { |item| item.text.strip }
    assert_equal address, doc.at_css('[data-reviewed-address]').text.strip
    form = doc.at_css("form[action='#{student_graduate_email_invitations_path(@student)}'][method='post']")
    assert form, 'Create form posts to the issuing route'
    assert_equal address, form.at_css('input[type="hidden"][name="reviewed_address"]')['value']
    mode = form.at_css('input[type="hidden"][name="replacement"]')&.[]('value')
    replacement ? assert_equal('1', mode) : assert_nil(mode)
    %w[email_identity_verified email_address_confirmed].each do |id|
      box = form.at_css("input[type='checkbox'][id='#{id}'][required]")
      assert box, "#{id} required"
      assert_nil box['checked']
    end
    assert_includes form.at_css('label[for="email_address_confirmed"]').text, address
    assert_equal [replacement ? 'Create replacement email invitation' : 'Create email invitation'],
      form.css('input[type="submit"], button').map { |item| item.name == 'button' ? item.text.strip : item['value'] }
    assert_equal [['Change address', staff_student_graduate_connections_path(@student)], ['Cancel', staff_student_graduate_connections_path(@student)]],
      doc.css('main a[data-review-exit]').map { |link| [link.text.strip, link['href']] }
    refute_includes response.body, 'Share this invitation once'
    assert_nil doc.at_css('a[href*="token="]')
  end

  def assert_stale(name = 'stale')
    assert_response :unprocessable_entity
    assert_equal 'stale', Nokogiri::HTML(response.body).at_css('[data-review-error]')&.[]('data-review-error'), name.to_s
    assert_nil Nokogiri::HTML(response.body).at_css('input[name="reviewed_address"]'), name.to_s
  end

  def main_text
    Nokogiri::HTML(response.body).at_css('main').text
  end

  def counts
    [GraduateEmailApproval.count, GraduateEmailChallenge.count, Delayed::Job.count, GraduateEmailAuditEvent.count, GraduateSession.count]
  end
end
