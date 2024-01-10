# frozen_string_literal: true

FactoryGirl.define do
  factory :student, class: Student, parent: :user do
    role User::STUDENT
    sisid { FactoryGirl.generate(:random_student_id).to_s }
    association :created_by, factory: :user
  end
end
