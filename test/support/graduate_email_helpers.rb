# frozen_string_literal: true
require_relative 'graduate_email_safe_artifacts'

raise 'Test helper unavailable' unless Rails.env.test?

module GraduateEmailHelpers
  def otp_code_for(public_id:)
    @codes&.delete(public_id)
  end

  def self.included(base)
    base.prepend GraduateEmailSafeArtifacts
    base.setup { ActionMailer::Base.deliveries.clear }
    base.teardown { ActionMailer::Base.deliveries.clear }
  end
end
