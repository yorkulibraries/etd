# frozen_string_literal: true

class WordCountValidator < ActiveModel::EachValidator
  ## USAGE
  # validates :summary, maximum: 30, word_count: true
  # validates :about_author, minimum: 25, word_count: true
  # validates :annotation, in: 10..30, word_count: true

  def validate_each(record, attribute, value)
    maximum = options[:maximum]
    minimum = options[:minimum]
    between = options[:in]

    # puts "VALUE: #{value}"
    return if value.blank?

    word_count = value.scan(/[\w-]+/).size

    if maximum.is_a?(Integer) && word_count.to_i > maximum.to_i
      record.errors[attribute] << (options[:message] || " exceeds maxmimum count of #{maximum} words")
    elsif minimum.is_a?(Integer) && word_count.to_i < minumum.to_i
      record.errors[attribute] << (options[:message] || " has less than mimumum (#{maximum}) number of words")
    elsif between.is_a?(Range) && (word_count.to_i < range.begin || word_count.to_i > range.end)
      record.errors[attribute] << (options[:message] || " must have between #{range.begin} and #{range.end} words")
    end
  end
end
