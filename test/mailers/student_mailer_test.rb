# frozen_string_literal: true

require 'test_helper'

class StudentMailerTest < ActionMailer::TestCase
  test 'approved embargo decision email is text only and goes only to the request contact address' do
    request = create(:embargo_request,
                     status: :approved,
                     contact_email: 'request-contact@example.com',
                     rationale: 'Confidential sponsor terms must not be disclosed.',
                     contact_phone: '416-555-0123',
                     supervisor_email: 'supervisor@example.com',
                     approved_until: Date.new(2027, 7, 27),
                     decided_at: Time.current,
                     decided_by: create(:user))
    document = create(:embargo_request_document, embargo_request: request, name: 'Confidential supervisor letter.pdf')

    mail = StudentMailer.embargo_decision_email(request)

    assert_equal ['request-contact@example.com'], mail.to
    assert_equal 'Your ETD embargo request was approved', mail.subject
    assert_match 'July 27, 2027', mail.body.encoded
    assert_match %r{http://etd\.me\.ca/my/thesis/#{request.thesis.id}/status}, mail.body.encoded
    assert_equal 'text/plain', mail.mime_type
    assert_empty mail.attachments
    assert_no_match request.rationale, mail.body.encoded
    assert_no_match request.contact_phone, mail.body.encoded
    assert_no_match request.graduate_program_director_name, mail.body.encoded
    assert_no_match request.graduate_program_director_email, mail.body.encoded
    assert_no_match request.supervisor_name, mail.body.encoded
    assert_no_match request.supervisor_email, mail.body.encoded
    assert_no_match document.name, mail.body.encoded
  end

  test 'declined embargo decision email includes notes but not confidential request fields' do
    request = create(:embargo_request,
                     status: :declined,
                     contact_email: 'request-contact@example.com',
                     rationale: 'Confidential sponsor terms must not be disclosed.',
                     contact_phone: '416-555-0123',
                     supervisor_email: 'supervisor@example.com',
                     decision_notes: 'The stated basis does not meet the embargo criteria.',
                     decided_at: Time.current,
                     decided_by: create(:user))

    mail = StudentMailer.embargo_decision_email(request)

    assert_equal ['request-contact@example.com'], mail.to
    assert_equal 'Your ETD embargo request was declined', mail.subject
    assert_match request.decision_notes, mail.body.encoded
    assert_match %r{http://etd\.me\.ca/my/thesis/#{request.thesis.id}/status}, mail.body.encoded
    assert_equal 'text/plain', mail.mime_type
    assert_empty mail.attachments
    assert_no_match request.rationale, mail.body.encoded
    assert_no_match request.contact_phone, mail.body.encoded
    assert_no_match request.graduate_program_director_name, mail.body.encoded
    assert_no_match request.graduate_program_director_email, mail.body.encoded
    assert_no_match request.supervisor_name, mail.body.encoded
    assert_no_match request.supervisor_email, mail.body.encoded
  end

  context 'as admin' do
    setup do
      @user = create(:user, role: User::ADMIN)
      @student = create(:student, email: 'stu1@me.ca', name: 'John Daily')
      AppSettings.email_welcome_allow = true
      AppSettings.email_welcome_subject = "email_welcome_subject"
      AppSettings.email_status_change_allow = true
      AppSettings.email_status_change_subject = "email_status_change_subject"
      AppSettings.email_from = "noreply@yorku.ca"

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
