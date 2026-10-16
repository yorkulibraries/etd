# frozen_string_literal: true

# Select durable storage without touching Active Job or inspecting tables at boot.
Delayed::Worker.backend = :active_record

# Per-payload limits (one attempt, 30 seconds, destroy failed) live on the two
# custom graduate jobs. Do not change global retries, queues or Active Job.
