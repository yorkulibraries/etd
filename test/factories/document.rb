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

  factory :document_for_file_naming, class: Document do
    sequence(:name) { |n| "document #{n}" }
    supplemental true
    association :thesis, factory: :thesis
    association :user, factory: :student
  end
  
  factory :document_for_file_naming_2, class: Document do
    sequence(:name) { |n| "document #{n}" }
    supplemental true
    association :thesis, factory: :thesis
    association :user, factory: :student
  end

  factory :document_licence, class: Document do
    sequence(:name) { |n| "document #{n}" }
    file { Rack::Test::UploadedFile.new('test/fixtures/files/pdf-document.pdf') }
    usage :licence
    supplemental true
    association :thesis, factory: :thesis
    association :user, factory: :user
  end

end
