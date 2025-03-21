# frozen_string_literal: true

FactoryGirl.define do
  factory :gem_record do
    studentname   { FactoryGirl.generate(:random_name) }
    sisid         { FactoryGirl.generate(:random_student_id) }
    emailaddress  { FactoryGirl.generate(:random_email) }
    eventtype     GemRecord::PHD_EXAM
    eventdate     { 21.days.ago }
    examresult    GemRecord::ACCEPTED
    examdate      { 10.days.ago }
    title         { FactoryGirl.generate(:random_string) }
    program       { FactoryGirl.generate(:random_string) }
    superv        { FactoryGirl.generate(:random_name) }
    seqgradevent  { FactoryGirl.generate(:random_seqgradevent) }

    after(:create) do |gem_record|
      FactoryGirl.create_list(:committee_member, 3, gem_record: gem_record)
    end
  end
end
