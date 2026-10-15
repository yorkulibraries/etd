# frozen_string_literal: true

module GraduateEmail
  module Address
    # Conservative individual ASCII addr-spec, shared by storage and future send paths.
    def self.normalize(input:)
      return unless input.is_a?(String) && input.ascii_only?
      return if input.match?(/[\r\n]/)

      value = input.gsub(/\A[ \t\v\f]+|[ \t\v\f]+\z/, '').downcase
      return if value.bytesize > 254 || value.match?(/[\x00-\x20\x7f]/)
      local, domain, extra = value.split('@', -1)
      return if extra || local.to_s.empty? || local.bytesize > 64 || domain.to_s.empty?
      return unless local.match?(/\A[a-z0-9!\#$%&'*+\/=\?^_`{|}~-]+(?:\.[a-z0-9!\#$%&'*+\/=\?^_`{|}~-]+)*\z/)
      labels = domain.split('.', -1)
      return if labels.any? { |label| label.start_with?('xn--') }
      return unless labels.size >= 2 && labels.all? { |label| label.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/) }
      return unless labels.last.match?(/\A[a-z]{2,63}\z/)
      parsed = Mail::Address.new(value)
      value if parsed.address == value && parsed.display_name.nil? && Array(parsed.comments).empty?
    rescue Mail::Field::ParseError, ArgumentError
      nil
    end
  end
end
