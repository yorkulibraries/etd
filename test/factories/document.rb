FactoryGirl.define do
  factory :document do
    sequence(:name) { |n| "document #{n}" }
    file { fixture_file_upload(Rails.root + 'test/fixtures/files/image-example.jpg', 'image/jpg') }
    supplemental true

    association :thesis, factory: :thesis
    association :user, factory: :user
  end
end
