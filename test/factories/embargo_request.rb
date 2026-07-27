# frozen_string_literal: true

FactoryGirl.define do
  factory :embargo_request do
    association :thesis
    request_type :new_request
    status :draft
    reason :intellectual_property_contract
    rationale 'The sponsor agreement requires delayed publication.'
    requested_duration_months 12
    contact_phone '416-555-0123'
    contact_email 'student@example.com'
    graduate_program_director_name 'Graduate Program Director'
    graduate_program_director_email 'gpd@example.com'
    supervisor_name 'Supervisor Name'
    supervisor_email 'supervisor@example.com'

    factory :submitted_embargo_request do
      status :submitted
      submitted_at { Time.current }

      after(:create) do |request|
        create(:document, thesis: request.thesis, user: request.thesis.student,
                          embargo_request_id: request.id, usage: :embargo_letter,
                          supplemental: true,
                          file: Rack::Test::UploadedFile.new('test/fixtures/files/pdf-document.pdf'))
      end
    end
  end
end
