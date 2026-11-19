# frozen_string_literal: true

module StudentsHelper
  # The one alternate (non-YorkU) email to show staff. When the student signs in
  # with an email address, that address is the one in use, so it is shown;
  # otherwise the address on the student record. Pass connection: nil to show
  # only the record (staff who cannot manage sign-in).
  def alternate_email_list(student, connection, empty: nil)
    return "#{connection.normalized_address} (used for email sign-in)" if connection

    student.email_external.presence || empty.to_s
  end

  def audit_change_value(value)
    case value
    when nil
      '(blank)'
    when String
      value.empty? ? '(blank)' : value
    when true
      'Yes'
    when false
      'No'
    when Array
      value.empty? ? '(blank)' : value.map { |item| audit_change_value(item) }.join(', ')
    when Hash
      return '(blank)' if value.empty?

      value.map do |field, item|
        "#{field.to_s.humanize}: #{audit_change_value(item)}"
      end.join(', ')
    else
      value.to_s
    end
  end
end
