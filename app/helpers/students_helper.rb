# frozen_string_literal: true

module StudentsHelper
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
