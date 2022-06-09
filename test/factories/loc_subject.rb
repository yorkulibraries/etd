FactoryGirl.define do
  factory :loc_subject do
    sequence (:name) { |n| "subject #{n}" }
    category "business"
    code 1234
    callnumber "LZ 23 A.29"
  end
end
