# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: 'noreply@yorku.ca'
  if AppSettings.email_from
    default from: AppSettings.email_from
  end
  layout 'mailer'
end
