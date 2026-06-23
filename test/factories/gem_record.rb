# frozen_string_literal: true

FactoryBot.define do
  factory :gem_record do
    studentname   { FactoryBot.generate(:random_name) }
    sisid         { FactoryBot.generate(:random_student_id) }
    emailaddress  { FactoryBot.generate(:random_email) }
    eventtype { GemRecord::PHD_EXAM }
    eventdate     { 21.days.ago }
    examresult { GemRecord::ACCEPTED }
    examdate      { 10.days.ago }
    title         { FactoryBot.generate(:random_string) }
    program       { FactoryBot.generate(:random_string) }
    superv        { FactoryBot.generate(:random_name) }
    seqgradevent  { FactoryBot.generate(:random_seqgradevent) }

    after(:create) do |gem_record|
      FactoryBot.create_list(:committee_member, 3, gem_record: gem_record)
    end
  end
end
