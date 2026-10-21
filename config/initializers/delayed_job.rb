# frozen_string_literal: true

# Select durable storage without touching Active Job or inspecting tables at boot.
Delayed::Worker.backend = :active_record

# Per-payload limits (one attempt, 30 seconds, destroy failed) live on the two
# custom graduate jobs. Do not change global retries, queues or Active Job.

# Only the two dedicated foreground processes opt in. Web/default workers keep
# their existing defaults. A stale backend lock is reclaimable after 30 seconds;
# the payload state still prevents a claimed delivery/notice from resending.
if ENV['GRADUATE_EMAIL_WORKER'] == '1'
  raise 'Graduate worker queue configuration rejected' unless ENV['QUEUES'] == 'graduate_email,graduate_email_notice'

  ENV['QUIET'] = '1' # jobs:work also writes raw backend messages to stdout unless quiet
  Delayed::Worker.max_run_time = 30
  Delayed::Worker.max_attempts = 1
  Delayed::Worker.destroy_failed_jobs = true
  # Delayed Job normally logs job names, IDs and exception backtraces. Dedicated
  # worker logging drops ALL backend messages; only fixed heartbeat/category
  # records below reach the journal. No general application logger is changed.
  Delayed::Worker.logger = Logger.new(File::NULL)
  plugin = Class.new(Delayed::Plugin) do
    callbacks do |lifecycle|
      lifecycle.before(:loop) do |_worker|
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        last = Thread.current[:graduate_email_heartbeat]
        if last.nil? || now - last >= 30
          $stdout.puts 'graduate_email worker_heartbeat'
          $stdout.flush
          Thread.current[:graduate_email_heartbeat] = now
        end
      end
      lifecycle.after(:error) { |_worker, _job| $stdout.puts 'graduate_email worker_error' }
    end
  end
  Delayed::Worker.plugins << plugin
end
