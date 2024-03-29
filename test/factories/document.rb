# frozen_string_literal: true

FactoryGirl.define do
  factory :document do
    sequence(:name) { |n| "document #{n}" }
    file { Rack::Test::UploadedFile.new('test/fixtures/files/image-example.jpg') }
    supplemental true
    association :thesis, factory: :thesis
    association :user, factory: :user
  end

  factory :document_for_naming, class: Document do
    sequence(:name) { |n| "document #{n}" }
    supplemental true
    association :thesis, factory: :thesis
    association :user, factory: :student_with_last_name
  end
end
