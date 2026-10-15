# frozen_string_literal: true
require_relative 'graduate_email_safe_artifacts'

module GraduateEmailHelpers
  def self.included(base)
    base.prepend GraduateEmailSafeArtifacts
    base.setup { ActionMailer::Base.deliveries.clear }
    base.teardown { ActionMailer::Base.deliveries.clear }
  end
end
