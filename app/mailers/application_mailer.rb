# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  FALLBACK_FROM_ADDRESS = 'noreply@yorku.ca'

  default from: -> { default_from_address }
  layout 'mailer'

  private

  def default_from_address
    AppSettings.email_from.to_s.strip.presence || FALLBACK_FROM_ADDRESS
  end
end
