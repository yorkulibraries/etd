# frozen_string_literal: true
raise 'Test helper unavailable' unless Rails.env.test?
require 'open3'
require 'json'
require_relative 'graduate_email_delivery_helpers'
require_relative 'graduate_oauth_flow'

module GraduateEmailDeliveryProcessHelpers
  def start_delivery_worker(row, barrier: 'none', hold: false, outcome: 'ACCEPT', limit: 1)
    parent_socket, child_socket = UNIXSocket.pair
    input, output, waiter = Open3.popen2e(RbConfig.ruby, '-S', 'bundle', 'exec', 'rails', 'runner',
      'test/support/graduate_email_delivery_worker.rb', 3 => child_socket)
    child_socket.close
    release = Queue.new
    received = Queue.new
    server = Thread.new do
      encoded = Marshal.load(parent_socket)
      message = Mail.read_from_string(encoded)
      capture_message_for(row.public_id, message)
      received << true
      release.pop if hold
      parent_socket.puts outcome
      parent_socket.flush
    rescue EOFError, IOError, Errno::EPIPE, Errno::ECONNRESET
      received << false
    end
    worker = {input: input, output: output, waiter: waiter, socket: parent_socket,
      server: server, release: release, received: received}
    (@delivery_workers ||= []) << worker
    input.puts JSON.generate(database: ActiveRecord::Base.connection_db_config.configuration_hash.slice(:adapter, :database), barrier: barrier, limit: limit)
    input.flush
    assert_equal 'DELIVERY_READY', delivery_marker(worker)
    input.puts 'START'
    input.flush
    worker
  end

  def capture_message_for(id, message)
    @capturing_id = id
    capture_message(message)
  ensure
    @capturing_id = nil
  end

  def delivery_marker(worker)
    Timeout.timeout(30) do
      loop do
        line = worker[:output].gets
        raise 'Worker ended before barrier' unless line
        return line.strip if line.start_with?('DELIVERY_')
      end
    end
  end

  def finish_delivery_worker(worker)
    assert_equal 'DELIVERY_DONE', delivery_marker(worker)
    assert Timeout.timeout(10) { worker[:waiter].value.success? }, 'Worker did not finish'
  end

  def kill_delivery_worker(worker)
    Process.kill('KILL', worker[:waiter].pid)
    assert Timeout.timeout(10) { worker[:waiter].value.signaled? }, 'Worker was not killed'
  end

  def cleanup_delivery_workers
    (@delivery_workers || []).each do |worker|
      if worker[:waiter].alive?
        Process.kill('KILL', worker[:waiter].pid) rescue Errno::ESRCH
        worker[:waiter].join(5)
      end
      worker[:release] << true
      worker[:socket].close rescue IOError
      worker[:input].close rescue IOError
      worker[:output].close rescue IOError
      worker[:server].join(2)
      worker[:server].kill if worker[:server].alive?
    end
    @delivery_workers = []
  end

  def assert_crash(barrier, state, accepted: false)
    row = challenge(request_code)
    worker = start_delivery_worker(row, barrier: barrier)
    assert_equal 'DELIVERY_NETWORK', delivery_marker(worker) if accepted
    assert_equal "DELIVERY_BARRIER #{barrier}", delivery_marker(worker)
    kill_delivery_worker(worker)
    assert_equal state, row.reload.state
    code = otp_code_for(public_id: row.public_id)
    assert_equal accepted, !code.nil?
    assert_equal accepted, eligible?(row) if state != 'sending' || accepted
    if accepted
      assert matches?(row, code)
    else
      refute eligible?(row) if state == 'claimed' || state == 'queued'
    end
    # Release queue ownership and explicitly reenqueue same ID. Both persisted
    # copies execute in a new worker, proving state rather than queue lock safety.
    Delayed::Job.where(queue: 'graduate_email').update_all(locked_at: nil, locked_by: nil)
    Delayed::Job.enqueue(GraduateEmailDeliveryJob.new(row.public_id), queue: 'graduate_email')
    second = start_delivery_worker(row, limit: 10)
    if state == 'queued'
      assert_equal 'DELIVERY_NETWORK', delivery_marker(second)
    end
    finish_delivery_worker(second)
    assert_equal state == 'queued' ? 'sent' : state, row.reload.state
    assert_equal accepted || state == 'queued' ? 1 : 0, @mail_messages.size
    assert_nil @approval.reload.consumed_at
    assert_equal 0, GraduateSession.count
    puts "DELIVERY_COUNTS crash_#{barrier} accepted=#{@mail_messages.size}"
  end
end
