# frozen_string_literal: true
require_relative '../support/graduate_email_browser_case'

class GraduateEmailManagementTest < GraduateEmailBrowserCase
  test 'initial_management_requires_recipient_confirmation_and_identity_checkbox' do
    browser_ppy_login(@actor)
    visit staff_student_graduate_connections_path(@student)
    assert_selector 'h2', text: 'Approve email sign-in'
    assert_no_selector '#email_identity_verified'
    fill_in 'Approved sign-in address', with: 'approved@example.com'
    fill_in 'Confirm approved address', with: 'different@example.com'
    click_button 'Review address'
    assert_current_path review_student_graduate_email_invitations_path(@student)
    assert_selector '[role="alert"][data-review-error="mismatch"]'
    assert_no_button 'Create email invitation'
    assert_equal 0, GraduateEmailApproval.uncached { GraduateEmailApproval.count }
    fill_in 'Approved sign-in address', with: 'Approved@Example.com'
    fill_in 'Confirm approved address', with: 'APPROVED@example.com'
    click_button 'Review address'
    assert_selector 'h1', text: 'Review email sign-in address'
    assert_equal 'approved@example.com', find('[data-reviewed-address]').text.strip
    assert_required_checkbox 'email_identity_verified'
    assert_required_checkbox 'email_address_confirmed'
    assert_text 'The invitation is for exactly approved@example.com'
    click_button 'Create email invitation'
    assert_current_path review_student_graduate_email_invitations_path(@student)
    assert_equal 0, GraduateEmailApproval.uncached { GraduateEmailApproval.count }, 'Browser requires both confirmations'
    check 'email_identity_verified'
    check 'email_address_confirmed'
    click_button 'Create email invitation'
    assert_selector 'h1', text: 'Share this invitation once'
    assert_equal 'approved@example.com', find('[data-approved-address]').text.strip
    assert_equal 1, GraduateEmailApproval.uncached { GraduateEmailApproval.count }
    assert_equal 0, Delayed::Job.where(queue: GraduateEmail::Limits::QUEUE).count
  end

  test 'staff_review_revise_cancel_stale_tab_and_conflicts_never_issue' do
    other = create(:student)
    issue_approval(student: other, address: 'shared@example.com')
    active_owner = create(:student)
    connection = GraduateEmailConnection.create!(student: active_owner, approved_by: @actor,
      normalized_address: 'active@example.com', verified_at: Time.current)
    GraduateEmailActiveAddress.create!(student: active_owner, connection: connection, normalized_address: 'active@example.com')
    own = -> { GraduateEmailApproval.uncached { GraduateEmailApproval.where(student_id: @student.id).count } }
    browser_ppy_login(@actor)
    visit staff_student_graduate_connections_path(@student)
    fill_in 'Approved sign-in address', with: 'Shared@Example.com'
    fill_in 'Confirm approved address', with: 'shared@example.com'
    click_button 'Review address'
    assert_selector '[role="alert"][data-review-error="pending_elsewhere"]'
    assert_selector 'a[data-conflict-record]', text: 'Open the other student record'
    assert_no_text other.name
    assert_no_selector 'input[name="reviewed_address"]'
    [false, true].each { |mobile| clean_browser_artifact('staff-conflict', mobile: mobile) }
    fill_in 'Approved sign-in address', with: 'active@example.com'
    fill_in 'Confirm approved address', with: 'ACTIVE@example.com'
    click_button 'Review address'
    assert_selector '[role="alert"][data-review-error="active_elsewhere"]'
    assert_no_text active_owner.name
    fill_in 'Approved sign-in address', with: 'mine@example.com'
    fill_in 'Confirm approved address', with: 'mine@example.com'
    click_button 'Review address'
    assert_selector '[data-reviewed-address]', text: 'mine@example.com'
    click_link 'Change address'
    assert_current_path staff_student_graduate_connections_path(@student)
    assert_selector 'h2', text: 'Approve email sign-in'
    assert_equal 0, own.call
    fill_in 'Approved sign-in address', with: 'mine@example.com'
    fill_in 'Confirm approved address', with: 'mine@example.com'
    click_button 'Review address'
    click_link 'Cancel'
    assert_current_path staff_student_graduate_connections_path(@student)
    assert_equal 0, own.call
    visit staff_student_graduate_connections_path(@student)
    fill_in 'Approved sign-in address', with: 'mine@example.com'
    fill_in 'Confirm approved address', with: 'mine@example.com'
    click_button 'Review address'
    review_window = current_window
    second = open_new_window
    within_window(second) { visit staff_student_graduate_connections_path(@student) }
    second.close
    switch_to_window(review_window)
    check 'email_identity_verified'
    check 'email_address_confirmed'
    click_button 'Create email invitation'
    assert_selector '[role="alert"][data-review-error="stale"]'
    assert_equal 0, own.call, 'A review left in another tab cannot issue'
    fill_in 'Approved sign-in address', with: 'mine@example.com'
    fill_in 'Confirm approved address', with: 'mine@example.com'
    click_button 'Review address'
    check 'email_identity_verified'
    check 'email_address_confirmed'
    click_button 'Create email invitation'
    assert_selector 'h1', text: 'Share this invitation once'
    assert_equal 'mine@example.com', find('[data-approved-address]').text.strip
    assert_equal 1, own.call
  end

  test 'staff_without_management_permission_cannot_approve' do
    @actor.update!(role: User::STAFF)
    browser_ppy_login(@actor)
    visit staff_student_graduate_connections_path(@student)
    assert_current_path unauthorized_path
    assert_equal 0, GraduateEmailApproval.count
  end
  test 'fgs_replacement_keeps_old_access_until_new_mailbox_verifies' do
    enrolled_connection
    request_login
    _, code = run_mail_worker
    enter_code(code)
    assert_current_path student_view_index_path
    Capybara.using_session(:fgs_recovery) do
      browser_ppy_login(@actor)
      visit staff_student_graduate_connections_path(@student)
      assert_selector 'h2', text: 'Replace or recover email sign-in'
      fill_in 'Approved sign-in address', with: 'new@example.com'
      fill_in 'Confirm approved address', with: 'NEW@example.com'
      click_button 'Review address'
      assert_equal 'new@example.com', find('[data-reviewed-address]').text.strip
      assert_text 'The current address stays usable until the new mailbox is verified.'
      check 'email_identity_verified'
      check 'email_address_confirmed'
      click_button 'Create replacement email invitation'
      assert_selector 'h1', text: 'Share this invitation once'
      assert_equal 'new@example.com', find('[data-approved-address]').text.strip
    end
    visit student_view_details_path
    assert_text @student.name
    assert_nil @connection.reload.revoked_at
    approval = GraduateEmailApproval.order(:id).last
    assert_equal @connection.id, approval.replacement_of_connection_id
    GraduateEmail::Revocation.approval!(approval: approval, actor: @actor, impersonating: false)
    visit student_view_details_path
    assert_text @student.name
  end

  test 'replacement_revokes_old_dormant_sessions_and_notifies_only_old_address' do
    enrolled_connection
    request_login
    old_row, old_code = run_mail_worker
    enter_code(old_code)
    assert_current_path student_view_index_path
    # Leave original browser dormant while a second browser proves new mailbox.
    Capybara.using_session(:recovery) do
      approval, token = issue_approval(address: 'new@example.com', replacement: true)
      visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
      assert_current_path '/graduate/email/verify'
      send_first_code
      row, code = run_mail_worker
      enter_code(code)
      assert_current_path student_view_index_path
      visit student_view_details_path
      assert_text @student.name
      assert approval.reload.consumed_at
      assert_equal 'consumed', row.reload.state
      assert_equal 1, GraduateEmailNotice.count
    end
    visit student_view_details_path
    assert_current_path graduate_login_path
    assert_nil GraduateEmail::Verification.redeem!(challenge_public_id: old_row.public_id,
      browser_token: SecureRandom.hex(32), code: old_code, ip: @ip)
    notice = GraduateEmailNotice.sole
    GraduateAuthenticationMailer.stub(:transport_class, @transport) do
      Delayed::Worker.new(queues: ['graduate_email_notice']).run(Delayed::Job.where(queue: 'graduate_email_notice').sole)
    end
    assert @mail_messages.last.to == ['approved@example.com'], 'Old recipient only'
    assert_safe_absent(@mail_messages.last.encoded, 'new@example.com', old_code, 'http://', 'https://')
    assert_equal 'sent', notice.reload.state
  end

  test 'fgs_revoke_cancels_approval_challenges_mapping_and_sessions' do
    enrolled_connection
    previous_test_mode = OmniAuth.config.test_mode
    OmniAuth.config.test_mode = true
    browser_mock_provider(uid: 'task6-independent-google')
    GraduateIdentity.create!(student: @student, linked_by: @actor, provider: 'google_oauth2', uid: 'task6-independent-google')
    request_login
    _, code = run_mail_worker
    enter_code(code)
    assert_current_path student_view_index_path
    approval, = issue_approval(address: 'pending@example.com', replacement: true)
    Capybara.using_session(:staff_revoke) do
      browser_ppy_login(@actor)
      visit staff_student_graduate_connections_path(@student)
      assert_required_checkbox "remove_email_#{@connection.id}"
      check "remove_email_#{@connection.id}"
      click_button 'Remove email connection'
      assert_current_path staff_student_graduate_connections_path(@student)
      assert_text 'The email sign-in connection was removed'
    end
    visit student_view_details_path
    assert_current_path graduate_login_path
    assert @connection.reload.revoked_at
    assert approval.reload.revoked_at
    assert_equal 0, GraduateEmailActiveAddress.count
    assert_equal 0, GraduateSession.where(authentication_method: 'email', revoked_at: nil).count
    click_button 'Continue with Google'
    assert_current_path student_view_index_path
    visit student_view_details_path
    assert_text @student.name
  ensure
    OmniAuth.config.test_mode = previous_test_mode
    OmniAuth.config.mock_auth.clear
  end

  test 'contact_edit_does_not_change_authentication' do
    enrolled_connection
    thesis = create(:thesis, student: @student)
    request_login
    _, code = run_mail_worker
    enter_code(code)
    assert_current_path student_view_thesis_process_path(thesis, Thesis::PROCESS_BEGIN)
    fill_in 'student_email_external', with: 'contact-only@example.com'
    click_button 'Continue'
    assert_current_path student_view_thesis_process_path(thesis, Thesis::PROCESS_UPDATE)
    assert_equal 'contact-only@example.com', @student.reload.email_external
    visit graduate_connections_path
    assert_text 'Verified address: approved@example.com'
    assert_no_button 'Remove email connection'
    assert_no_selector 'input[name="address"]'
    assert_equal 'approved@example.com', GraduateEmailActiveAddress.sole.normalized_address
    visit student_view_details_path
    assert_text @student.name
  end

  test 'staff_impersonation_and_student_cannot_manage_email' do
    enrolled_connection
    browser_ppy_login(@actor)
    visit login_as_student_path(@student)
    visit staff_student_graduate_connections_path(@student)
    assert_current_path unauthorized_path
    browser_fresh_session
    @actor.update!(role: User::STAFF)
    browser_ppy_login(@actor)
    visit staff_student_graduate_connections_path(@student)
    assert_current_path unauthorized_path
    browser_fresh_session
    @actor.update!(role: User::MANAGER)
    request_login
    _, code = run_mail_worker
    enter_code(code)
    assert_current_path student_view_index_path
    visit staff_student_graduate_connections_path(@student)
    assert_current_path unauthorized_path
    visit graduate_connections_path
    assert_no_button 'Remove email connection'
    assert_no_button 'Create replacement email invitation'
  end

  test 'email_student_has_ownership_download_and_thesis_edit_boundaries' do
    enrolled_connection
    own = create(:thesis, student: @student)
    other = create(:student)
    foreign = create(:thesis, student: other)
    request_login
    _, code = run_mail_worker
    enter_code(code)
    assert_current_path student_view_thesis_process_path(own, Thesis::PROCESS_BEGIN)
    visit student_thesis_path(other, foreign)
    assert_current_path unauthorized_path
    [Thesis::ACCEPTED, Thesis::PUBLISHED].each do |status|
      own.update!(status: status)
      visit edit_student_thesis_path(@student, own)
      assert_current_path unauthorized_path
    end
    visit student_view_details_path
    assert_text @student.name
    documents = [own, foreign].map do |thesis|
      create(:document, thesis: thesis, user: thesis.student, supplemental: false,
        file: Rack::Test::UploadedFile.new('test/fixtures/files/pdf-document.pdf', 'application/pdf'))
    end
    versions = [own, foreign].map { |thesis| thesis.create_submission_snapshot!(thesis.student) }
    result = browser_download(download_student_thesis_document_path(@student, own, documents[0]))
    assert_equal 200, result['status']
    assert_equal Digest::SHA256.file(documents[0].file.path).hexdigest, result['digest']
    denied = browser_download(download_student_thesis_document_path(other, foreign, documents[1]))
    assert denied['denied'], 'Foreign current download denied'
    versions.each do |version|
      doc = version.submission_documents.first
      denied = browser_download(student_thesis_submission_version_submission_document_path(version.thesis.student, version.thesis, version, doc))
      assert denied['denied'], 'Student historical staff-view download denied'
    end
    assert_equal 404, browser_download(documents[0].file_url)['status']
  ensure
    documents&.each { |doc| FileUtils.rm_rf(File.dirname(doc.file.path)) }
    versions&.each { |version| version.submission_documents.each { |doc| FileUtils.rm_rf(File.dirname(doc.file.path)) } }
  end

  test 'desktop_mobile_long_address_staff_confirmation_and_all_notice_states' do
    long_address = ('a' * 64) + '@' + ('b' * 60) + '.example.org'
    @student.update!(email: long_address, email_external: long_address)
    browser_ppy_login(@actor)
    visit staff_student_graduate_connections_path(@student)
    [false, true].each do |mobile|
      assert_selector 'h2', text: 'Approve email sign-in'
      fill_in 'Approved sign-in address', with: long_address
      fill_in 'Confirm approved address', with: long_address
      clean_browser_artifact('staff-confirmation', mobile: mobile)
    end
    click_button 'Review address'
    assert_equal long_address, find('[data-reviewed-address]').text.strip
    [false, true].each do |mobile|
      %w[email_identity_verified email_address_confirmed].each do |id|
        assert_required_checkbox id
        find("##{id}").send_keys(:space)
        assert find("##{id}").checked?, 'keyboard confirmation'
      end
      clean_browser_artifact('staff-review', mobile: mobile)
      %w[email_identity_verified email_address_confirmed].each { |id| uncheck id }
    end
    assert_equal 0, GraduateEmailApproval.uncached { GraduateEmailApproval.count }
    connection = GraduateEmailConnection.create!(student: @student, approved_by: @actor,
      normalized_address: long_address, verified_at: Time.current)
    GraduateEmailActiveAddress.create!(student: @student, connection: connection, normalized_address: long_address)
    %w[queued claimed sent failed].each do |state|
      replacement = GraduateEmailConnection.create!(student: @student, approved_by: @actor,
        normalized_address: state + '@example.org', verified_at: Time.current, revoked_at: Time.current)
      GraduateEmailNotice.create!(old_connection: connection, replacement_connection: replacement, state: state)
    end
    visit staff_student_graduate_connections_path(@student)
    [false, true].each do |mobile|
      assert_selector '[data-email-notice-state]', count: 4
      assert_text 'Unknown (claimed; no automatic retry)'
      assert_text 'Accepted by mail transport; delivery unconfirmed'
      assert_text 'Failed; no automatic retry'
      assert_required_checkbox "remove_email_#{connection.id}"
      clean_browser_artifact('staff-recovery', mobile: mobile)
      clean_browser_artifact('notice-states', mobile: mobile)
    end
    browser_fresh_session
    request_login(long_address)
    _, code = run_mail_worker
    enter_code(code)
    assert_current_path student_view_index_path
    visit graduate_connections_path
    assert_no_button 'Remove email connection'
    assert_no_button 'Connect Google'
    [false, true].each { |mobile| clean_browser_artifact('student-connection', mobile: mobile) }
  end

  private

  def browser_download(path)
    page.driver.browser.execute_async_script(<<~JS, path)
      const path = arguments[0], done = arguments[arguments.length - 1];
      fetch(path, {credentials: 'same-origin'}).then(async response => {
        const bytes = await response.arrayBuffer();
        const digest = await crypto.subtle.digest('SHA-256', bytes);
        done({status: response.status, denied: new URL(response.url).pathname === '/unauthorized',
          digest: Array.from(new Uint8Array(digest)).map(x => x.toString(16).padStart(2, '0')).join('')});
      }).catch(() => done({status: -1, denied: false}));
    JS
  end

end
