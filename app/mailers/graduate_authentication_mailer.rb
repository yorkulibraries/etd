# frozen_string_literal: true
require 'mail'
require 'erb'

# Explicit class builders, deliberately NOT ActionMailer action dispatch. This
# renderer has no instrumentation containing arguments/body or raw render errors.
# Other application mailers and shared loggers are untouched.
class GraduateAuthenticationMailer
  class << self
    def code(recipient:, code:, expires_at:)
      raise GraduateAuthentication::Rejected unless code.is_a?(String) && code.match?(/\A[0-9]{6}\z/) && expires_at.is_a?(Time)

      builder = new
      builder.instance_variable_set(:@code, code.dup.freeze)
      builder.instance_variable_set(:@expires_at, expires_at.dup.freeze)
      builder.send(:build, recipient: recipient, template: 'code', subject: 'Your graduate sign-in code')
    rescue StandardError
      raise GraduateAuthentication::Rejected, 'Graduate mail unavailable', cause: nil
    end

    def access_changed(old_connection:)
      raise GraduateAuthentication::Rejected unless old_connection.is_a?(GraduateEmailConnection) && old_connection.persisted?

      new.send(:build, recipient: old_connection.normalized_address, template: 'access_changed', subject: 'Graduate email access changed')
    rescue StandardError
      raise GraduateAuthentication::Rejected, 'Graduate mail unavailable', cause: nil
    end

    def transport_class
      Mail::SMTP
    end
  end

  private

  def build(recipient:, template:, subject:)
    normalized = GraduateEmail::Address.normalize(input: recipient)
    raise GraduateAuthentication::Rejected unless GraduateEmail.delivery_configured? && normalized == recipient && normalized
    raise GraduateAuthentication::Rejected unless ActiveRecord::Base.connection.open_transactions.zero?

    message = Mail::Message.new
    message.to = [normalized]
    message.from = [GraduateEmail.from_address]
    message.subject = subject
    message.content_type = 'text/plain; charset=UTF-8'
    message.body = render_to_string(template: template)
    message.delivery_method(self.class.transport_class, GraduateEmail.smtp_settings.dup)
    message.perform_deliveries = true
    message.raise_delivery_errors = true
    message
  end

  # Fixed templates only, no secret locals or ActionView render events. ERB
  # receives a private binding and the code never enters a rendering payload.
  def render_to_string(template:)
    raise GraduateAuthentication::Rejected unless %w[code access_changed].include?(template)

    ERB.new(File.read(Rails.root.join('app/views/graduate_authentication_mailer', "#{template}.text.erb"))).result(binding)
  end
end
