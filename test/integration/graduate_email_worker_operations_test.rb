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
  private
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
