# frozen_string_literal: true
# No DB/Rails/mail: exercise installed Worker start/work_off/perform callbacks.
require 'logger'
require 'delayed_job'
require 'delayed_job_active_record'
require 'stringio'
require 'json'
role = ARGV.fetch(0)
raise 'Probe role rejected' unless %w[dedicated ordinary].include?(role)
ENV['GRADUATE_EMAIL_WORKER'] = role == 'dedicated' ? '1' : nil
ENV['QUEUES'] = 'graduate_email,graduate_email_notice'
defaults = [Delayed::Worker.max_run_time, Delayed::Worker.max_attempts, Delayed::Worker.destroy_failed_jobs]
load File.expand_path('../../config/initializers/delayed_job.rb', __dir__)
# This shutdown plugin queries storage; all other installed lifecycle stays real.
Delayed::Worker.plugins.delete(Delayed::Plugins::ClearLocks)
clock = 0.0
Process.define_singleton_method(:clock_gettime) { |*| clock }
rows = []
output = StringIO.new
output.define_singleton_method(:puts) do |line|
  rows << [clock, line]
  super(line)
end
worker = Delayed::Worker.new(quiet: true, sleep_delay: 1)
jobs = 0
worker.define_singleton_method(:reserve_job) { jobs < 100 ? Object.new : nil }
# Only execution is synthetic. reserve_and_run_one_job and :perform are real.
worker.define_singleton_method(:run) { |_job| jobs += 1; clock += 1; true }
worker.define_singleton_method(:sleep) { |_| clock += 1; stop if clock >= 200 }
worker.define_singleton_method(:reload!) {}
original = $stdout
begin
  $stdout = output
  worker.start
ensure
  $stdout = original
end
beats = rows.select { |_, line| line == 'graduate_email worker_heartbeat' }.map(&:first)
checks = {jobs: jobs == 100, simulated_seconds: clock == 200,
  static_output: rows.all? { |_, line| line == 'graduate_email worker_heartbeat' }}
if role == 'dedicated'
  checks.merge!(busy: beats.count { |t| t <= 100 } >= 4,
    idle: beats.count { |t| t > 100 } >= 3,
    rate_bound: beats.each_cons(2).all? { |a, b| (b-a).between?(30, 31) },
    no_initial_gap: beats.first == 0, no_final_gap: beats.last && clock-beats.last <= 30,
    bounded_count: beats.size <= 7)
else
  checks.merge!(no_heartbeat: beats.empty?, defaults_unchanged:
    defaults == [Delayed::Worker.max_run_time, Delayed::Worker.max_attempts, Delayed::Worker.destroy_failed_jobs])
end
puts JSON.generate(role: role, jobs: jobs, simulated_seconds: clock, heartbeat_seconds: beats, checks: checks)
exit(checks.values.all? ? 0 : 1)
