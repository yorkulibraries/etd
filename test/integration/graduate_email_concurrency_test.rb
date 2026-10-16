# frozen_string_literal: true
require 'test_helper'
require 'open3'
require 'timeout'
require 'json'
require_relative '../support/graduate_email_admission_helpers'

# F07 F08 F10 F11: independent processes rendezvous before any product transaction.
class GraduateEmailConcurrencyTest < ActionDispatch::IntegrationTest
  include GraduateEmailAdmissionHelpers
  self.use_transactional_tests = false
  setup { setup_admission }
  teardown { teardown_admission }

  test 'two_workers_cannot_exceed_send_budget' do
    assert_send_race
  end

  test 'two_failures_cannot_lose_a_count' do
    8.times { assert_equal :allowed, fail_verify(now: @instant) }
    outputs = race('failure', [@browser, SecureRandom.hex(32)])
    assert_equal 2, outputs.count { |lines| lines.include?('ADMISSION_COUNTED_FAILURE') }
    %w[verify_address verify_student verify_ip].each { |kind| assert_equal 10, events(kind).count }
    assert_equal 2, GraduateEmailCooldown.count
    assert_equal :limited, admit_verify(now: @instant)
    puts 'ADMISSION_COUNTS failure workers=2 failures_per_key=10 cooldowns=2'
  end

  test 'sqlite_write_first_lock_prevents_read_then_write_race' do
    # Also execute on MySQL to prove the common transaction entry protocol.
    assert_send_race
  end

  private

  def assert_send_race
    tokens = [@browser, SecureRandom.hex(32)]
    previous = tokens.map do |token|
      GraduateEmailChallenge.create!(public_id: SecureRandom.hex(32), student: @student,
        connection: @connection, purpose: 'login', state: 'sent', generation: 1,
        browser_digest: GraduateEmail::Challenges.browser_digest(browser_token: token, purpose: :login),
        address_key: address_key, code_digest: 'd' * 64, expires_at: @instant + 5.minutes)
    end
    GraduateEmail::Control.synchronize do
      4.times { events('send_address').create!(key_digest: address_key, occurred_at: @instant - 2.minutes) }
    end
    outputs = race('send', tokens)
    assert_equal 2, outputs.count { |lines| lines.include?('ADMISSION_SENT_REQUEST') }
    assert_equal 5, events('send_address').count
    assert_equal 2, events('request_ip').count
    assert_equal 2, events('admission_send').count
    assert_equal 1, GraduateEmailChallenge.where(state: 'queued').count
    assert_equal 1, GraduateEmailChallenge.where(state: 'noop').count
    assert_equal ['sent', 'superseded'], previous.map { |row| row.reload.state }.sort
    assert_equal 2, Delayed::Job.where(queue: 'graduate_email').count
    assert_equal 4, GraduateEmailChallenge.count
    assert_equal 0, GraduateEmailAuditEvent.count
    puts 'ADMISSION_COUNTS send workers=2 address_events=5 real_jobs=1 noop_jobs=1 retained_jobs=2 retained_challenges=4'
  end

  def race(action, tokens)
    children = []
    tokens.each do |token|
      input, output, waiter = Open3.popen2e(RbConfig.ruby, '-S', 'bundle', 'exec', 'rails', 'runner',
        'test/support/graduate_email_admission_race.rb')
      input.puts JSON.generate(action: action, browser: token, student_id: @student.id, now: @instant.iso8601,
        database: ActiveRecord::Base.connection_db_config.configuration_hash.slice(:adapter, :database))
      input.flush
      children << [input, output, waiter]
    end
    children.each { |_, output, _| assert_equal 'ADMISSION_READY', marker(output) }
    children.each { |input, _, _| input.puts 'START'; input.flush }
    children.map do |_, output, waiter|
      first = marker(output)
      assert_includes ['ADMISSION_SENT_REQUEST', 'ADMISSION_COUNTED_FAILURE'], first
      lines = [first, marker(output)]
      assert_includes lines, 'ADMISSION_WRITE_FIRST'
      assert Timeout.timeout(25) { waiter.value.success? }, 'independent admission process failed'
      lines
    end
  ensure
    (children || []).each do |input, output, waiter|
      input.close unless input.closed?
      output.close unless output.closed?
      if waiter.alive?
        begin
          Process.kill('KILL', waiter.pid)
        rescue Errno::ESRCH
          # The process exited between alive? and kill.
        ensure
          waiter.join(5)
        end
      end
    end
  end

  def marker(output)
    Timeout.timeout(25) do
      loop do
        line = output.gets
        raise 'Admission child ended before marker' unless line
        return line.strip if line.start_with?('ADMISSION_')
      end
    end
  end
end
