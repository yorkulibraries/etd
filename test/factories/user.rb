# frozen_string_literal: true

FactoryGirl.define do
  factory :user do
    username { FactoryGirl.generate(:random_username) }
    name { FactoryGirl.generate(:random_name) }
    email { FactoryGirl.generate(:random_email) }
    created_by_id nil
    role User::STAFF
    blocked false
  end
end
