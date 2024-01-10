# frozen_string_literal: true

class TestJob < ActiveJob::Base
  queue_as :default

  def perform(*args)
    Rails.logger.debug "#{self.class.name}: I'm performing my job with arguments: #{args.inspect}"
  end
end
