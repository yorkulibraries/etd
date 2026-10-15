# frozen_string_literal: true

# Select durable storage without touching Active Job or inspecting tables at boot.
Delayed::Worker.backend = :active_record
