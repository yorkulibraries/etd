# frozen_string_literal: true
require 'test_helper'
require_relative '../support/graduate_email_flow_helpers'

# Policy (FGS, 2026-11-03): a graduate may connect email sign-in by proving
# they own an address already on exactly one active student record, primary
# or secondary. Proof is still the emailed code. The page never reveals
# whether an address matched.
class GraduateEmailRecordMatchTest < ActionDispatch::IntegrationTest
  include GraduateEmailFlowHelpers
  self.use_transactional_tests = false
  setup do
    setup_flow
    @student.update_columns(email: 'grad@yorku.ca', email_external: 'Grad.Personal@Example.com')
    @browser = SecureRandom.hex(32)
  end
  teardown { teardown_delivery }

  def request_for(address, browser: @browser)
    challenge(GraduateEmail::Challenges.request!(purpose: :login, browser_token: browser, ip: @ip, address: address))
  end

  def deliver_and_redeem(row, browser: @browser)
    deliver_row(row)
    code = otp_code_for(public_id: row.public_id)
    assert code, 'Code was emailed'
    GraduateEmail::Verification.redeem!(challenge_public_id: row.public_id, browser_token: browser, code: code, ip: @ip)
  end

  test 'secondary_email_on_the_record_connects_after_the_emailed_code' do
    row = request_for('grad.personal@example.com')
    assert_equal 'enroll', row.purpose
    assert_equal 'queued', row.state
    approval = GraduateEmailApproval.find(row.approval_id)
    assert_equal ['record', nil, 'grad.personal@example.com', @student.id],
      [approval.source, approval.approved_by_id, approval.normalized_address, approval.student_id]
    assert_equal 0, GraduateEmailConnection.count, 'Nothing connects before the code is entered'
    grant = deliver_and_redeem(row)
    assert grant, 'Code redeems'
    assert_equal @student.id, grant.student_id
    connection = GraduateEmailConnection.find(grant.connection_id)
    assert_equal ['record', nil, 'grad.personal@example.com'], [connection.source, connection.approved_by_id, connection.normalized_address]
    assert_equal connection.id, GraduateEmailActiveAddress.find_by(student_id: @student.id).connection_id
    assert approval.reload.consumed_at
    assert GraduateEmailAuditEvent.where(event: 'enrollment', outcome: 'consumed', connection_id: connection.id).exists?

    travel 2.minutes
    returning = request_for('grad.personal@example.com', browser: SecureRandom.hex(32))
    assert_equal ['login', connection.id], [returning.purpose, returning.connection_id], 'Later sign-ins use the connection'
  end

  test 'primary_email_and_any_address_in_a_multi_address_field_match' do
    assert_equal 'enroll', request_for('grad@yorku.ca').purpose
    GraduateEmailChallenge.delete_all
    GraduateEmailApproval.delete_all
    GraduateEmailLimitEvent.delete_all
    @student.update_columns(email_external: 'first@example.com, second@example.com')
    row = request_for('SECOND@example.com')
    assert_equal 'enroll', row.purpose
    assert_equal 'second@example.com', GraduateEmailApproval.find(row.approval_id).normalized_address
  end

  test 'unknown_shared_staff_and_partial_addresses_never_send' do
    other = create(:student)
    other.update_columns(email_external: 'shared@example.com')
    @student.update_columns(email_external: 'shared@example.com')
    staff = create(:user, role: User::MANAGER)
    staff.update_columns(email: 'staff-only@example.com')
    ['nobody@example.com', 'shared@example.com', 'staff-only@example.com', 'personal@example.com', 'grad@yorku'].each do |address|
      row = request_for(address)
      assert_equal ['noop', 'noop'], [row.purpose, row.state], address
    end
    assert_equal 0, GraduateEmailApproval.count
    assert_empty Delayed::Job.where(queue: GraduateEmail::Limits::QUEUE).select { |job| job.payload_object.is_a?(GraduateEmailDeliveryJob) &&
      GraduateEmailChallenge.find_by(public_id: job.payload_object.challenge_public_id)&.state != 'noop' }
  end

  test 'blocked_students_and_students_with_an_existing_connection_do_not_match' do
    @student.update_columns(blocked: true)
    assert_equal 'noop', request_for('grad.personal@example.com').state
    @student.update_columns(blocked: false)
    enrolled_connection
    @mapping.destroy!
    assert_equal 'noop', request_for('grad.personal@example.com').state, 'One email sign-in per student; FGS handles changes'
    assert_equal 0, GraduateEmailApproval.count
  end

  test 'an_address_connected_or_pending_for_another_student_does_not_match' do
    other = create(:student)
    issue_approval(student: other, address: 'grad.personal@example.com')
    assert_equal 'noop', request_for('grad.personal@example.com').state
  end

  test 'record_change_before_delivery_or_redemption_fails_closed' do
    row = request_for('grad.personal@example.com')
    @student.update_columns(email_external: 'changed@example.com')
    deliver_row(row)
    assert_nil otp_code_for(public_id: row.public_id), 'No code once the record no longer lists the address'
    assert_equal 'failed', row.reload.state

    travel 2.minutes
    @student.update_columns(email_external: 'grad.personal@example.com')
    row = request_for('grad.personal@example.com', browser: (browser = SecureRandom.hex(32)))
    deliver_row(row)
    code = otp_code_for(public_id: row.public_id)
    assert code
    @student.update_columns(email_external: 'changed@example.com')
    assert_nil GraduateEmail::Verification.redeem!(challenge_public_id: row.public_id, browser_token: browser, code: code, ip: @ip)
    assert_equal 0, GraduateEmailConnection.count
  end

  test 'resend_reuses_one_pending_record_approval' do
    first = request_for('grad.personal@example.com')
    travel 61.seconds
    second = request_for('grad.personal@example.com')
    assert_equal first.approval_id, second.approval_id
    assert_equal 'superseded', first.reload.state
    assert_equal 1, GraduateEmailApproval.count
  end

  test 'record_approvals_cannot_be_used_as_invitation_links_or_by_another_browser' do
    row = request_for('grad.personal@example.com')
    deliver_row(row)
    code = otp_code_for(public_id: row.public_id)
    assert_nil GraduateEmail::Verification.redeem!(challenge_public_id: row.public_id, browser_token: SecureRandom.hex(32), code: code, ip: @ip)
    approval = GraduateEmailApproval.find(row.approval_id)
    token = SecureRandom.urlsafe_base64(32)
    approval.update_columns(token_digest: Digest::SHA256.hexdigest(token))
    assert_raises(GraduateAuthentication::Rejected, 'A record match never works as an invitation link') do
      GraduateEmail::Enrollment.intent!(token: token, browser_token: SecureRandom.hex(32))
    end
  end

  test 'matched_and_unmatched_requests_render_the_same_page' do
    bodies = ['grad.personal@example.com', 'nobody@example.com'].map do |address|
      reset!
      host! '127.0.0.1:3210'
      get '/graduate/email'
      post '/graduate/email/challenges', params: {address: address}
      assert_response :accepted
      Nokogiri::HTML(response.body).at_css('main').text.squish
    end
    assert_equal bodies.first, bodies.last
    assert_includes bodies.first, 'If you are a current student, sign in with Passport York.'
    assert_includes bodies.first, 'contact the Faculty of Graduate Studies'
  end
end
