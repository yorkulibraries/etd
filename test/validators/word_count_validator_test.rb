# frozen_string_literal: true

require 'test_helper'

class WordCountValidatorTest < ActiveSupport::TestCase
  class Subject
    include ActiveModel::Model

    attr_accessor :summary, :about_author, :annotation

    validates :summary, word_count: { maximum: 2 }
    validates :about_author, word_count: { minimum: 2 }
    validates :annotation, word_count: { in: 2..3 }
  end

  should 'allow blank values and values inside the configured limits' do
    subject = Subject.new(summary: '', about_author: 'one two', annotation: 'one two three')

    assert subject.valid?
  end

  should 'reject values above the maximum word count' do
    subject = Subject.new(summary: 'one two three')

    assert_not subject.valid?
    assert subject.errors[:summary].any? { |message| message.include?('max') }
  end

  should 'reject values below the minimum word count' do
    subject = Subject.new(about_author: 'one')

    assert_not subject.valid?
    assert subject.errors[:about_author].any? { |message| message.include?('minimum') }
  end

  should 'reject values outside an inclusive word-count range' do
    subject = Subject.new(annotation: 'one two three four')

    assert_not subject.valid?
    assert subject.errors[:annotation].any? { |message| message.include?('between') }
  end
end
