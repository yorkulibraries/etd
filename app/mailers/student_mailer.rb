# frozen_string_literal: true

class StudentMailer < ApplicationMailer
  def invitation_email(student)
    @template = Liquid::Template.parse(AppSettings.email_welcome_body) # Parses and compiles the template

    ## setup variables
    @date = Date.today.strftime('%b %e, %Y')
    @date_short = Date.today.strftime('%m-%d-%Y')
    @student = student
    @application_url = root_url

    @message_subject = AppSettings.email_welcome_subject

    recipients = []
    recipients << student.email
    if student.email_external.present?
      student.email_external.split(/[\s,]+/).each do |address|
        recipients << address
      end
    end

    mail to: map_recipients(recipients), subject: @message_subject if AppSettings.email_welcome_allow
  end

  def status_change_email(student, thesis, old_status, new_status, additional_recipients = [], custom_message = nil)
    @template = Liquid::Template.parse(AppSettings.email_status_change_body) # Parses and compiles the template

    @student = student
    @thesis = thesis
    @old_status = old_status
    @new_status = new_status
    @custom_message = custom_message
    @application_url = root_url

    @message_subject = AppSettings.email_status_change_subject

    recipients = additional_recipients << student.email
    if student.email_external.present?
      student.email_external.split(/[\s,]+/).each do |address|
        recipients << address
      end
    end

    mail to: map_recipients(recipients), subject: @message_subject if AppSettings.email_status_change_allow
  end

  def map_recipients(recipients)
    filtered = []
    recipients.each do |r|
      email = r.gsub("stu@etd.library.yorku.ca", "@yorku.ca")
      if email =~ /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\Z/i
        filtered << email
      end
    end
    return filtered
  end
end
