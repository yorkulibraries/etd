FactoryGirl.define do
  factory :document do
    sequence(:name) { |n| "document #{n}" }
    file { Rack::Test::UploadedFile.new('test/fixtures/files/image-example.jpg') }
    supplemental true
    association :thesis, factory: :thesis
    association :user, factory: :user
  end
end
