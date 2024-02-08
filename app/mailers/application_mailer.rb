# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: 'noreply@etd.library.yorku.ca'
  layout 'mailer'
end
