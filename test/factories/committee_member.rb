FactoryGirl.define do
  factory :committee_member do
    sequence (:first_name) { |n| "committee #{n}"}
    sequence (:last_name) { |n| "member #{n}"}
    role CommitteeMember::CHAIR
    association :thesis, factory: :thesis
  end
end
