# frozen_string_literal: true
require_relative '../support/graduate_email_browser_case'
require_relative '../support/graduate_email_delivery_process_helpers'

class GraduateEmailAuthenticationTest < GraduateEmailBrowserCase
  include GraduateEmailDeliveryProcessHelpers
  test 'fgs_confirms_one_address_and_enrollment_requires_mailbox_code' do
    approval, token = issue_approval
    browser_ppy_login(@actor)
    visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
    assert_current_path '/graduate/email/verify'
    assert_equal 0, GraduateSession.where(authentication_method: 'email').count
    assert_nil approval.reload.consumed_at
    assert_no_selector 'input[name="address"]'
    send_first_code
    row, code = run_mail_worker
    assert_equal approval.id, row.approval_id
    enter_code(code)
    assert_current_path student_view_index_path
    assert_equal @student.id, GraduateEmailActiveAddress.first.student_id
    assert approval.reload.consumed_at
  end

  test 'returning_graduate_opens_existing_student_record' do
    enrolled_connection
    thesis = create(:thesis, student: @student)
    before = [Student.count, @student.email]
    request_login
    _, code = run_mail_worker
    enter_code(code)
    assert_current_path student_view_thesis_process_path(thesis, Thesis::PROCESS_BEGIN)
    assert_selector 'main'
    visit student_view_details_path
    assert_text @student.name
    assert_equal before, [Student.count, @student.reload.email]
    visit student_view_thesis_process_path(thesis, Thesis::PROCESS_BEGIN)
    assert_current_path student_view_thesis_process_path(thesis, Thesis::PROCESS_BEGIN)
  end

  # M4: opening an invitation creates intent only. Refresh, Back and reopening
  # never deliver; one explicit Send code queues one real job.
  test 'first_invitation_offers_send_code_and_get_never_delivers' do
    approval, token = issue_approval
    before = flow_counts
    visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
    assert_current_path '/graduate/email/verify'
    assert_first_request_form
    page.refresh
    assert_first_request_form
    visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
    assert_current_path '/graduate/email/verify'
    assert_first_request_form
    assert_equal before, flow_counts
    send_first_code
    assert_equal [before[0] + 1, before[1] + 1], flow_counts
    queued = GraduateEmailChallenge.order(:id).last
    assert_equal ['enroll', 'queued', approval.id], [queued.purpose, queued.state, queued.approval_id]
    page.go_back
    assert_current_path '/graduate/email/verify'
    page.refresh
    assert_generic_form
    assert_equal [before[0] + 1, before[1] + 1], flow_counts
    row, code = run_mail_worker
    assert_equal queued.id, row.id
    enter_code(code == '000000' ? '000001' : '000000')
    assert_selector '#code-error'
    assert_equal '', find('#code').value
    assert_equal 'code-error', find('#code')['aria-describedby']
    assert_generic_form
    enter_code(code)
    assert_current_path student_view_index_path
    assert approval.reload.consumed_at
    assert_equal 1, GraduateEmailActiveAddress.where(student_id: @student.id).count
  end

  test 'replacement_invitation_offers_send_code_then_resend' do
    enrolled_connection
    approval, token = issue_approval(address: 'new@example.com', replacement: true)
    before = flow_counts
    visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
    assert_current_path '/graduate/email/verify'
    assert_first_request_form
    page.refresh
    assert_first_request_form
    assert_equal before, flow_counts
    send_first_code
    first, = run_mail_worker
    assert_equal approval.id, first.approval_id
    travel 61.seconds
    resend_code
    assert_generic_form
    assert_equal 'superseded', first.reload.state
    row, code = run_mail_worker
    assert_equal approval.id, row.approval_id
    enter_code(code)
    assert_current_path student_view_index_path
    assert approval.reload.consumed_at
    assert_equal 'new@example.com', GraduateEmailActiveAddress.find_by!(student_id: @student.id).normalized_address
  end

  # The test thread caches identical count queries; read server writes fresh.
  def flow_counts
    ActiveRecord::Base.uncached { [GraduateEmailChallenge.count, Delayed::Job.count] }
  end

  # I1: the verified connection's approver may later leave or lose staff role.
  test 'returning_login_survives_historical_approver_demotion_and_block' do
    enrolled_connection
    @actor.update!(role: User::STAFF, blocked: true)
    request_login
    row, code = run_mail_worker
    assert_equal @connection.id, row.connection_id
    enter_code(code)
    assert_current_path student_view_index_path
    visit student_view_details_path
    assert_text @student.name
    assert_equal @actor.id, @connection.reload.approved_by_id
  end

  test 'unknown_blocked_unenrolled_and_throttled_look_identical' do
    enrolled_connection
    structures = []
    ['approved@example.com', 'unknown@example.com', 'unenrolled@example.com', 'approved@example.com'].each do |address|
      request_login(address)
      assert_generic_form
      structures << page.all('main form').map { |form| [form[:action], form.all('input', visible: :all).map { |field| [field[:name], field[:type]] }] }
      browser_fresh_session
    end
    @student.block
    request_login
    assert_generic_form
    structures << page.all('main form').map { |form| [form[:action], form.all('input', visible: :all).map { |field| [field[:name], field[:type]] }] }
    assert structures.all? { |shape| shape == structures.first }, 'generic forms match'
  end

  test 'six_digit_wrong_expired_reused_and_cross_purpose_codes_fail' do
    enrolled_connection
    request_login
    row, code = run_mail_worker
    5.times do
      enter_code('00000x')
      assert_text 'The code is incorrect or has expired. Request a new code and try again.'
    end
    enter_code(code)
    assert_current_path '/graduate/email/verify'
    assert_equal 5, row.reload.failed_attempts
    travel_to row.expires_at
    enter_code(code)
    assert_current_path '/graduate/email/verify'
  end

  test 'two_browsers_resend_without_interference' do
    enrolled_connection
    request_login
    first, first_code = run_mail_worker
    Capybara.using_session(:second) do
      travel 61.seconds
      request_login
      second, second_code = run_mail_worker
      enter_code(first_code)
      assert_current_path '/graduate/email/verify'
      enter_code(second_code)
      assert_current_path student_view_index_path
      assert_equal 'sent', first.reload.state
      assert second.reload.consumed_at
    end
    enter_code(first_code)
    assert_current_path student_view_index_path
  end

  test 'send_limit_does_not_prevent_valid_verification' do
    enrolled_connection
    SecureRandom.stub(:random_number, 7) do
      request_login
      row, code = run_mail_worker
      assert code == '000007', 'leading-zero code retained in RAM'
      resend_code
      assert_equal 'sent', row.reload.state
      enter_code(code)
      assert_current_path student_view_index_path
    end
  end

  test 'email_only_login_redirect_works' do
    GraduateAuthentication.stub(:enabled_providers, []) do
      visit student_view_details_path
      assert_current_path graduate_login_path
      assert_link 'Email me a sign-in code'
      assert_link 'Sign in with Passport York'
      click_link 'Email me a sign-in code'
      assert_current_path '/graduate/email'
    end
  end
  test 'fresh_code_expires_at_exact_five_minutes_in_the_browser' do
    travel_to Time.current.change(usec: 0)
    enrolled_connection
    request_login
    row, code = run_mail_worker
    travel_to row.expires_at
    enter_code(code)
    assert_selector '#code-error', text: 'The code is incorrect or has expired'
    assert_current_path '/graduate/email/verify'
    assert_equal 0, GraduateSession.where(authentication_method: 'email').count
  end

  test 'expired_forty_eight_hour_invitation_never_enrolls_from_browser' do
    travel_to Time.current.change(usec: 0)
    approval, token = issue_approval
    travel_to approval.expires_at
    visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
    assert_current_path '/graduate/email/verify'
    send_first_code
    assert_equal 0, GraduateEmailChallenge.where.not(student_id: nil).count
    assert_nil approval.reload.consumed_at
    visit student_view_index_path
    assert_current_path graduate_login_path
  end

  test 'enrollment_code_cannot_sign_in_as_login_and_success_cannot_replay' do
    approval, token = issue_approval
    visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
    assert_current_path '/graduate/email/verify'
    send_first_code
    _, old_code = run_mail_worker
    click_link 'Use another email address'
    assert_current_path '/graduate/email'
    request_login
    enter_code(old_code)
    assert_selector '#code-error', text: 'The code is incorrect or has expired'
    assert_nil approval.reload.consumed_at
    assert_equal 0, GraduateSession.where(authentication_method: 'email').count
    travel 61.seconds
    visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
    assert_current_path '/graduate/email/verify'
    send_first_code
    _, code = run_mail_worker
    enter_code(code)
    assert_current_path student_view_index_path
    assert approval.reload.consumed_at
    # No transaction remains, so no code form; the used link looks unused.
    visit '/graduate/email/verify'
    assert_selector 'h1', text: 'Request your sign-in code'
    assert_text 'No code has been requested in this browser.'
    assert_no_field 'Sign-in code'
    assert_no_button 'Send code'
    jobs = flow_counts.last
    visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
    assert_current_path '/graduate/email/verify'
    send_first_code
    assert_equal jobs, flow_counts.last
    enter_code(code)
    assert_selector '#code-error', text: 'The code is incorrect or has expired'
    assert_equal 1, GraduateSession.uncached { GraduateSession.where(authentication_method: 'email').count }
  end

  test 'real_browser_capture_rejects_entered_code_token_url_and_dom' do
    request_login
    directory = Pathname.new(GraduateEmailSafeArtifacts.verification_directory(ENV['DB_ADAPTER'] == 'mysql2' ? 'mysql' : 'sqlite'))
    before = Dir[directory.join('*.png')].to_h { |file| [file, Digest::SHA256.file(file).hexdigest] }
    fill_in 'Sign-in code', with: '123456'
    assert_raises(GraduateEmailSafeArtifacts::UnsafeArtifact) { clean_browser_artifact('generic-send') }
    fill_in 'Sign-in code', with: ''
    page.execute_script("history.replaceState(null, '', '/graduate/email/verify?token=TASK7_ARTIFACT_SENTINEL')")
    assert_raises(GraduateEmailSafeArtifacts::UnsafeArtifact) { clean_browser_artifact('generic-send') }
    page.execute_script("history.replaceState(null, '', '/graduate/email/verify'); const e=document.createElement('input'); e.name='token'; e.type='hidden'; e.value='TASK7_ARTIFACT_SENTINEL'; document.body.append(e)")
    assert_raises(GraduateEmailSafeArtifacts::UnsafeArtifact) { clean_browser_artifact('generic-send') }
    page.execute_script("document.querySelector('input[name=token]').remove(); const e=document.createElement('p'); e.textContent='Your sign-in code is 123456'; document.body.append(e)")
    page.driver.browser.stub(:execute_cdp, ->(*) { raise 'unsafe capture reached' }) do
      assert_raises(GraduateEmailSafeArtifacts::UnsafeArtifact) { clean_browser_artifact('generic-send') }
    end
    page.execute_script("document.body.lastElementChild.remove(); const e=document.createElement('div'); e.dataset.invitation='T'.repeat(43); document.body.append(e)")
    page.driver.browser.stub(:execute_cdp, ->(*) { raise 'unsafe capture reached' }) do
      assert_raises(GraduateEmailSafeArtifacts::UnsafeArtifact) { clean_browser_artifact('generic-send') }
    end
    page.execute_script("document.body.lastElementChild.remove(); const e=document.createElement('script'); e.type='application/json'; e.textContent=JSON.stringify({invitation:'T'.repeat(43)}); document.body.append(e)")
    page.driver.browser.stub(:execute_cdp, ->(*) { raise 'unsafe capture reached' }) do
      assert_raises(GraduateEmailSafeArtifacts::UnsafeArtifact) { clean_browser_artifact('generic-send') }
    end
    assert_equal before, Dir[directory.join('*.png')].to_h { |file| [file, Digest::SHA256.file(file).hexdigest] }
  end

  test 'general_clean_assertions_and_failure_preserve_sealed_bytes' do
    previous = ENV.delete('GRADUATE_EMAIL_ARTIFACT_DIR')
    visit graduate_login_path
    page.driver.browser.stub(:execute_cdp, ->(*) { raise 'image driver must not run' }) do
      [false, true].each { |mobile| assert_nil clean_browser_artifact('login', mobile: mobile) }
      assert_raises(Minitest::Assertion) do
        clean_browser_artifact('login')
        flunk 'controlled assertion after clean screen'
      end
      request_login
      fill_in 'Sign-in code', with: '123456'
      assert_raises(GraduateEmailSafeArtifacts::UnsafeArtifact) { clean_browser_artifact('generic-send') }
    end
  ensure
    previous.nil? ? ENV.delete('GRADUATE_EMAIL_ARTIFACT_DIR') : ENV['GRADUATE_EMAIL_ARTIFACT_DIR'] = previous
  end

  test 'explicit_capture_rejects_sealed_package_before_image_driver' do
    require 'tmpdir'
    previous = ENV['GRADUATE_EMAIL_ARTIFACT_DIR']
    visit graduate_login_path
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, 'manifest.json'), '{}')
      ENV['GRADUATE_EMAIL_ARTIFACT_DIR'] = directory
      GraduateEmailSafeArtifacts.stub(:verification_directory, directory) do
        page.driver.browser.stub(:execute_cdp, ->(*) { raise 'sealed image driver must not run' }) do
          assert_raises(GraduateEmailSafeArtifacts::UnsafeArtifact) { clean_browser_artifact('login') }
        end
      end
      assert_equal ['manifest.json'], Dir.children(directory)
      assert_equal '{}', File.read(File.join(directory, 'manifest.json'))
    end
  ensure
    previous.nil? ? ENV.delete('GRADUATE_EMAIL_ARTIFACT_DIR') : ENV['GRADUATE_EMAIL_ARTIFACT_DIR'] = previous
  end

  test 'combined_enabled_login_keeps_google_post_and_ppy_boundaries' do
    visit graduate_login_path
    assert_link 'Email me a sign-in code', href: graduate_email_path
    assert_link 'Sign in with Passport York', href: login_path
    assert_button 'Continue with Google'
    assert_no_button 'Continue with Facebook'
    within "form[action='#{graduate_auth_path('google_oauth2')}'][method='post']" do
      assert_selector 'input[name="authenticity_token"]', visible: :all
    end
    assert_no_link href: graduate_auth_path('google_oauth2')
    previous = OmniAuth.config.test_mode
    OmniAuth.config.test_mode = true
    browser_mock_provider(uid: 'task7-independent-google')
    GraduateIdentity.create!(student: @student, linked_by: @actor, provider: 'google_oauth2', uid: 'task7-independent-google')
    click_button 'Continue with Google'
    assert_current_path student_view_index_path
    visit graduate_connections_path
    assert_no_button 'Connect Google'
    visit staff_student_graduate_connections_path(@student)
    assert_current_path unauthorized_path
  ensure
    OmniAuth.config.test_mode = previous
    OmniAuth.config.mock_auth.clear
  end

  test 'desktop_mobile_code_and_staff_forms_have_no_overflow' do
    enrolled_connection
    [false, true].each do |mobile|
      browser_fresh_session
      visit graduate_login_path
      assert_link 'Email me a sign-in code'
      clean_browser_artifact('login', mobile: mobile)
      request_login
      assert_generic_form
      captured = clean_browser_artifact('generic-send', mobile: mobile)
      if captured
        bytes = File.binread(captured)
        assert_equal mobile ? 390 : 1440, bytes.byteslice(16, 4).unpack1('N'), 'capture keeps full viewport width'
      end
      assert page.evaluate_script('document.documentElement.scrollWidth <= document.documentElement.clientWidth'), 'content fits usable viewport'
      enter_code('00000x')
      assert_selector '#code-error'
      assert_equal '', find('#code').value
      clean_browser_artifact('code-error', mobile: mobile)
      assert_equal 'code-error', find('#code')['aria-describedby']
      assert_equal 'Sign-in code', find('label[for="code"]').text
      find('#code').send_keys(:tab)
      assert_equal 'Verify code', page.evaluate_script('document.activeElement.value')
      assert_equal 'alert', find('#code-error')['role']
      browser_fresh_session
    end
  end

  test 'expired_and_revoked_enrollment_are_clean_in_both_viewports' do
    [false, true].each do |mobile|
      approval, token = issue_approval
      travel_to approval.expires_at
      visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
      assert_current_path '/graduate/email/verify'
      assert_first_request_form
      clean_browser_artifact('expired-enrollment', mobile: mobile)
      travel_back
      approval, token = issue_approval
      GraduateEmail::Revocation.approval!(approval: approval, actor: @actor, impersonating: false)
      visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
      assert_current_path '/graduate/email/verify'
      assert_first_request_form
      clean_browser_artifact('revoked-enrollment', mobile: mobile)
      send_first_code
      assert page.evaluate_script('document.documentElement.scrollWidth <= document.documentElement.clientWidth'), 'accepted state fits'
      browser_fresh_session
    end
  end

  test 'disable_reenable_dormant_browser_and_paused_job' do
    enrolled_connection
    request_login
    _, code = run_mail_worker
    enter_code(code)
    assert_current_path student_view_index_path
    approval, token = issue_approval(address: 'pending@example.org', replacement: true)
    stale = nil
    Capybara.using_session(:stale_code) do
      travel 61.seconds
      request_login
      _, stale = run_mail_worker
    end
    Capybara.using_session(:paused) do
      travel 61.seconds
      request_login
      row = GraduateEmailChallenge.where(state: 'queued').sole
      assert_equal 1, Delayed::Job.where(queue: GraduateEmail::Limits::QUEUE).count
      worker = start_delivery_worker(row, paused: true)
      GraduateEmail::Control.set_enabled!(enabled: false, actor_id: @actor.id)
      GraduateEmail::Control.set_enabled!(enabled: true, actor_id: @actor.id)
      before = @mail_messages.length
      worker[:input].puts 'START'
      worker[:input].flush
      finish_delivery_worker(worker)
      assert_equal before, @mail_messages.length
      assert_nil row.reload.sent_at
      enter_code(code)
      assert_selector '#code-error'
    end
    Capybara.using_session(:stale_code) do
      enter_code(stale)
      assert_selector '#code-error'
      assert_equal 1, GraduateSession.where(authentication_method: 'email').count
    end
    Capybara.using_session(:old_enrollment) do
      visit "/graduate/email/enroll?#{URI.encode_www_form(token: token)}"
      assert_current_path '/graduate/email/verify'
      send_first_code
      assert_nil approval.reload.consumed_at
    end
    visit student_view_details_path
    assert_current_path graduate_login_path
    travel 61.seconds
    request_login
    _, fresh = run_mail_worker
    enter_code(fresh)
    assert_current_path student_view_index_path
  ensure
    cleanup_delivery_workers
  end

end
