class StudentMailer < ApplicationMailer
  default from: "noreply@etd.library.yorku.ca"


  def invitation_email(student)

    @template = Liquid::Template.parse(AppSettings.email_welcome_body)  # Parses and compiles the template

    ## setup variables
    @date = Date.today.strftime("%b %e, %Y")
    @date_short = Date.today.strftime("%m-%d-%Y")
    @student = student

    @application_url = root_url

    @message_subject = AppSettings.email_welcome_subject

    if AppSettings.email_welcome_allow
      mail to: @student.email, subject: @message_subject
    end

  end


  def status_change_email(student, thesis, old_status, new_status, additional_recipients = [], custom_message = nil)

    @template = Liquid::Template.parse(AppSettings.email_status_change_body)  # Parses and compiles the template

    @student = student
    @thesis = thesis
    @old_status = old_status
    @new_status = new_status
    @custom_message = custom_message

    @message_subject =  AppSettings.email_status_change_subject

    recipients = additional_recipients << student.email

    if AppSettings.email_status_change_allow
      mail to: recipients, subject: @message_subject
    end

  end
end
