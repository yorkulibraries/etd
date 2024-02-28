# frozen_string_literal: true

FactoryGirl.define do
  factory :student, class: Student, parent: :user do
    role User::STUDENT
    sisid { FactoryGirl.generate(:random_student_id).to_s }
    association :created_by, factory: :user
  end

  factory :student_with_last_name, class: Student, parent: :user do
    role User::STUDENT
    sisid { FactoryGirl.generate(:random_student_id).to_s }
    association :created_by, factory: :user
    last_name { Faker::Name.last_name }
    first_name { Faker::Name.first_name }
    middle_name { Faker::Name.middle_name }
  end
end
