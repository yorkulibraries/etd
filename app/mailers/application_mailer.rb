# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: 'noreply@yorku.ca'
  layout 'mailer'
end
