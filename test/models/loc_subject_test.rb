# frozen_string_literal: true

require 'test_helper'

class LocSubjectTest < ActiveSupport::TestCase
  should 'create an loc subject' do
    subject = build(:loc_subject)

    assert subject.valid?, 'Valid subject is built'
    assert_difference 'LocSubject.count', 1 do
      subject.save
    end
  end

  should 'not create an invalid subject' do
    assert !build(:loc_subject, name: nil).valid?, 'Name is required'
    assert !build(:loc_subject, category: nil).valid?, 'Category is required'
  end

  should 'load subjects from subjects file' do
    file = 'lib/loc_subjects.txt'

    assert_difference 'LocSubject.count', 411, 'There are 432 lines in file and only 411 of them are categories' do
      LocSubject.load_from_file(file)
    end

    first = LocSubject.first
    last = LocSubject.last
    assert_equal 'AREA, ETHNIC, AND GENDER STUDIES', first.category
    assert_equal 'MATHEMATICAL AND PHYSICAL SCIENCES', last.category
  end
end
