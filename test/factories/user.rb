# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    username { FactoryBot.generate(:random_username) }
    name { FactoryBot.generate(:random_name) }
    email { FactoryBot.generate(:random_email) }
    created_by_id { nil }
    role { User::STAFF }
    blocked { false }
  end
end
