# frozen_string_literal: true

require 'test_helper'

class StudentMailerTest < ActionMailer::TestCase
  context 'as admin' do
    setup do
      @user = create(:user, role: User::ADMIN)
      @student = create(:student, email: 'stu1@me.ca', name: 'John Daily')
      AppSettings.email_welcome_allow = true
      AppSettings.email_welcome_subject = "email_welcome_subject"
      AppSettings.email_status_change_allow = true
      AppSettings.email_status_change_subject = "email_status_change_subject"

      # Empty every thing out
      ActionMailer::Base.deliveries = []
    end

    should 'send an invitation email' do
      mail = StudentMailer.invitation_email(@student).deliver_now
      assert !ActionMailer::Base.deliveries.empty?, "Shouldn't be empty"

      assert_equal AppSettings.email_welcome_subject, mail.subject
      assert_equal ['stu1@me.ca'], mail.to
      assert_equal AppSettings.email_from, mail.from.first
      # assert_match @student.name, mail.body.encoded ##FIXME
    end

    should 'send out a status notification email' do
      thesis = create(:thesis, student: @student, status: Thesis::OPEN)
      recipients = ['stu1@me.ca', 'stu2@me.ca']

      mail = StudentMailer.status_change_email(@student, thesis, Thesis::OPEN, Thesis::UNDER_REVIEW, recipients,
                                               'custom message').deliver_now
      assert !ActionMailer::Base.deliveries.empty?

      assert_equal AppSettings.email_status_change_subject, mail.subject
      assert_equal ( ['stu1@me.ca', 'stu2@me.ca'] << @student.email).size, mail.to.size
      assert_equal  AppSettings.email_from, mail.from.first
      # assert_match "custom message", mail.body.encoded ## FIXME
      # assert_match Thesis::OPEN, mail.body.encoded ## FIXME
      # assert_match @student.name, mail.body.encoded ## FIXME
    end

    should 'not send email if notification is disabled' do
      AppSettings.email_welcome_allow = false
      AppSettings.email_status_change_allow = false

      StudentMailer.status_change_email(@student, Thesis.new, Thesis::OPEN, Thesis::UNDER_REVIEW).deliver_now
      assert ActionMailer::Base.deliveries.empty?, 'should not work'

      StudentMailer.invitation_email(@student).deliver_now
      assert ActionMailer::Base.deliveries.empty?, 'should not work'
    end
  end
end
