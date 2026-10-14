# frozen_string_literal: true

class StudentMailer < ApplicationMailer
  def invitation_email(invitation)
    @template = Liquid::Template.parse(AppSettings.email_welcome_body) # Parses and compiles the template

    ## setup variables
    @date = Date.today.strftime('%b %e, %Y')
    @date_short = Date.today.strftime('%m-%d-%Y')
    @student = invitation.student
    @thesis_title = invitation.thesis&.title || invitation.gem_record&.title
    @invitation_expiry_date = invitation.expires_at.in_time_zone('Eastern Time (US & Canada)').strftime('%B %-d, %Y at %-I:%M %p %Z')
    @application_url = root_url

    @message_subject = AppSettings.email_welcome_subject

    recipients = []
    recipients << @student.email
    if @student.email_external.present?
      @student.email_external.split(/[\s,]+/).each do |address|
        recipients << address
      end
    end

    mail to: map_recipients(recipients), subject: @message_subject.strip if AppSettings.email_welcome_allow
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

    mail to: map_recipients(recipients), subject: @message_subject.strip if AppSettings.email_status_change_allow
  end

  def embargo_decision_email(request)
    @request = request
    @thesis = request.thesis
    @student = @thesis.student
    @status_url = student_view_thesis_process_url(@thesis, Thesis::PROCESS_STATUS)
    outcome = request.approved? ? 'approved' : 'declined'

    mail to: request.contact_email,
         subject: "Your ETD embargo request was #{outcome}"
  end

  def map_recipients(recipients)
    filtered = []
    recipients.each do |r|
      email = r.gsub("stu@etd.library.yorku.ca", "@yorku.ca")
      email = email.gsub("stu@etd.gmail.com", "@yorku.ca")
      if email =~ /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\Z/i
        filtered << email
      end
    end
    return filtered
  end
end
