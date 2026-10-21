# frozen_string_literal: true
require 'test_helper'
require_relative '../support/graduate_email_recovery_helpers'
require_relative '../support/graduate_email_delivery_process_helpers'

# O09: two actual jobs:work processes, fake SMTP only, no shell daemon wrapper.
class GraduateEmailWorkerOperationsTest < ActionDispatch::IntegrationTest
  include GraduateEmailRecoveryHelpers
  include GraduateEmailDeliveryProcessHelpers
  self.use_transactional_tests=false
  setup { setup_delivery }
  teardown do
    cleanup_delivery_workers
    teardown_delivery
  end
  test 'installed_lifecycle_heartbeats_cover_busy_and_idle_with_bounded_safe_output' do
    %w[dedicated ordinary].each do |role|
      text, status = Open3.capture2e(RbConfig.ruby, '-S', 'bundle', 'exec', 'ruby',
        'test/support/graduate_email_worker_lifecycle_probe.rb', role)
      result = JSON.parse(text)
      assert status.success?, 'Installed lifecycle heartbeat contract'
      assert result.fetch('checks').values.all?, 'Busy/idle rate and ordinary-worker contracts'
    end
  end

  test 'restart_reclaims_queued_but_not_claimed_delivery_on_both_dedicated_queues' do
    otp=challenge(request_code)
    replacement=GraduateEmailConnection.create!(student:@student,approved_by:@actor,normalized_address:'restart@example.com',verified_at:Time.current)
    notice=GraduateEmailNotice.create!(old_connection:@connection,replacement_connection:replacement,state:'queued')
    Delayed::Job.enqueue(GraduateEmailNoticeJob.new(notice.id),queue:'graduate_email_notice')
    sentinel=Delayed::Job.enqueue(GraduateEmailDeliveryJob.new(SecureRandom.hex(32)),queue:'default')
    # Both processes stop before job selection, then restart with persisted rows.
    first=2.times.map { start_ops_worker(otp,paused:true) }
    first.each { |w| kill_delivery_worker(w) }
    assert_equal 1,Delayed::Job.where(queue:'graduate_email').count
    assert_equal 1,Delayed::Job.where(queue:'graduate_email_notice').count
    second=2.times.map { start_ops_worker(otp) }
    wait_for { otp.reload.state=='sent' && notice.reload.state=='sent' }
    second.each { |w| stop_ops_worker(w) }
    assert_equal 2,@mail_messages.size
    assert_equal 0,Delayed::Job.where(queue:%w[graduate_email graduate_email_notice]).count
    assert Delayed::Job.exists?(sentinel.id)
    # New durable rows are each claimed and killed before SMTP. Stale backend
    # locks are advanced synthetically rather than sleeping for maxrun30.
    GraduateEmailLimitEvent.where(kind:'send_address').delete_all
    otp2=challenge(request_code(browser_token:SecureRandom.hex(32)))
    replacement2=GraduateEmailConnection.create!(student:@student,approved_by:@actor,normalized_address:'restart2@example.com',verified_at:Time.current)
    notice2=GraduateEmailNotice.create!(old_connection:@connection,replacement_connection:replacement2,state:'queued')
    Delayed::Job.enqueue(GraduateEmailNoticeJob.new(notice2.id),queue:'graduate_email_notice')
    claimed=2.times.map { start_ops_worker(otp2,barrier:'claimed') }
    claimed.each { |w| assert_equal 'DELIVERY_BARRIER claimed',delivery_marker(w) }
    assert_equal 'claimed',otp2.reload.state
    assert_equal 'claimed',notice2.reload.state
    digest=otp2.code_digest
    claimed.each { |w| kill_delivery_worker(w) }
    Delayed::Job.where(queue:%w[graduate_email graduate_email_notice]).update_all(locked_at:31.seconds.ago)
    third=2.times.map { start_ops_worker(otp2) }
    wait_for { Delayed::Job.where(queue:%w[graduate_email graduate_email_notice]).count.zero? }
    third.each { |w| stop_ops_worker(w) }
    assert_equal 2,@mail_messages.size
    assert_equal digest,otp2.reload.code_digest
    assert_equal 'claimed',otp2.state
    assert_equal 'claimed',notice2.reload.state
    assert Delayed::Job.exists?(sentinel.id)
  end
  # I2: fresh installed jobs:work processes, after every Rails initializer.
  # Missing/invalid configuration stops before any reservation; rows are kept.
  test 'dedicated_worker_refuses_start_without_configuration_and_retains_durable_work' do
    otp=challenge(request_code)
    replacement=GraduateEmailConnection.create!(student:@student,approved_by:@actor,normalized_address:'boot@example.com',verified_at:Time.current)
    notice=GraduateEmailNotice.create!(old_connection:@connection,replacement_connection:replacement,state:'queued')
    Delayed::Job.enqueue(GraduateEmailNoticeJob.new(notice.id),queue:'graduate_email_notice')
    durable=-> { [Delayed::Job.where(queue:%w[graduate_email graduate_email_notice]).order(:id).map(&:attributes),otp.reload.attributes,notice.reload.attributes] }
    before=durable.call
    assert_equal 2,before[0].size
    secret='I2_BOOT_SENTINEL'
    dedicated={'GRADUATE_EMAIL_WORKER'=>'1','QUEUES'=>'graduate_email,graduate_email_notice','SLEEP_DELAY'=>'1'}
    [{'GRADUATE_EMAIL_SMTP_ADDRESS'=>nil},
      {'GRADUATE_EMAIL_SMTP_USER_NAME'=>'worker','GRADUATE_EMAIL_SMTP_AUTHENTICATION'=>'plain','GRADUATE_EMAIL_SMTP_PASSWORD'=>"#{secret}\r\nRCPT"},
      {'GRADUATE_EMAIL_FROM'=>"#{secret}@example.org\r\nBcc: other@example.org"},
      {'GRADUATE_EMAIL_CODE_KEY'=>nil},{'GRADUATE_EMAIL_BASE_URL'=>"https://#{secret}.example.org/path"}].each do |bad|
      output,status=bounded_capture(dedicated.merge(bad),'rake','jobs:work')
      assert status && !status.success?,'Unconfigured dedicated worker refuses start'
      assert output.include?('Graduate worker delivery configuration rejected'),'Fixed start rejection'
      assert_safe_absent(output,secret,'c'*32,'l'*32,@connection.normalized_address,otp.public_id)
      assert_equal before,durable.call
    end
    # Ordinary boot and a default worker are unchanged without mail configuration.
    ordinary={'GRADUATE_EMAIL_WORKER'=>nil,'QUEUES'=>nil,'GRADUATE_EMAIL_SMTP_ADDRESS'=>nil,'GRADUATE_EMAIL_FROM'=>nil}
    output,status=bounded_capture(ordinary,'rails','runner','puts(GraduateEmail.delivery_configured? ? "BOOT_CONFIGURED" : "BOOT_UNCONFIGURED")')
    assert status&.success?,'Ordinary boot unchanged'
    assert output.include?('BOOT_UNCONFIGURED'),'Ordinary process boots without mail configuration'
    _,status=bounded_capture(ordinary.merge('QUEUES'=>'graduate_email_ordinary_probe'),'rake','jobs:workoff')
    assert status&.success?,'Default worker unchanged'
    assert_equal before,durable.call
    # Valid configuration with the feature disabled: start gate reads no control,
    # the security notice is delivered and the stale OTP fails closed.
    GraduateEmail::Control.set_enabled!(enabled:false,actor_id:@actor.id)
    worker=start_ops_worker(otp)
    wait_for { notice.reload.state=='sent' && Delayed::Job.where(queue:%w[graduate_email graduate_email_notice]).none? }
    stop_ops_worker(worker)
    assert_equal 1,@mail_messages.size
    assert_equal [@connection.normalized_address],@mail_messages.first.to
    assert_equal 'failed',otp.reload.state
    assert_nil otp.code_digest
  end
  private
  def bounded_capture(env,*command,seconds:120)
    Open3.popen2e(env,RbConfig.ruby,'-S','bundle','exec',*command,pgroup:true) do |input,stream,waiter|
      input.close
      reader=Thread.new { stream.read }
      unless waiter.join(seconds)
        begin
          Process.kill('KILL',-waiter.pid)
        rescue Errno::ESRCH
          nil
        end
        waiter.join(10)
        return [reader.join(10)&.value.to_s,nil]
      end
      [reader.value,waiter.value]
    end
  end
  def wait_for
    Timeout.timeout(30) { Thread.pass until yield }
  end
  def start_ops_worker(row,paused:false,barrier:'none')
    parent,child=UNIXSocket.pair
    input,output,waiter=Open3.popen2e({'GRADUATE_EMAIL_WORKER'=>'1','QUEUES'=>'graduate_email,graduate_email_notice','SLEEP_DELAY'=>'1'},
      RbConfig.ruby,'-S','bundle','exec','rails','runner','test/support/graduate_email_operations_worker.rb',3=>child)
    child.close
    release=Queue.new
    server=Thread.new do
      loop do
        message=Mail.read_from_string(Marshal.load(parent))
        capture_message_for(row.public_id,message)
        parent.puts 'ACCEPT';parent.flush
      end
    rescue EOFError,IOError,Errno::EPIPE,Errno::ECONNRESET
      nil
    end
    worker={input:input,output:output,waiter:waiter,socket:parent,server:server,release:release}
    (@delivery_workers||=[])<<worker
    input.puts JSON.generate(database:ActiveRecord::Base.connection_db_config.configuration_hash.slice(:adapter,:database),barrier:barrier)
    input.flush
    assert_equal 'DELIVERY_READY',delivery_marker(worker)
    unless paused
      input.puts 'START';input.flush
    end
    worker
  end
  def stop_ops_worker(worker)
    Process.kill('TERM',worker[:waiter].pid)
    Timeout.timeout(40){worker[:waiter].join}
    assert worker[:waiter].value.success?,'Foreground worker stops cleanly'
  end
end
