class ChagingStatusMailer < ApplicationMailer
  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.chaging_status_mailer.published.subject
  #
  def published(student_email)
    mail to: student_email, subject: 'The status of your thesis has been changed.'
  end
end
