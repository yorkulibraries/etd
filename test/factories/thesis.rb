# frozen_string_literal: true

FactoryGirl.define do
  factory :thesis do
    gem_record_event_id { FactoryGirl.generate(:random_seqgradevent) }

    title { FactoryGirl.generate(:random_string) }
    association :student, factory: :student
    assigned_to nil

    author { FactoryGirl.generate(:random_name) }
    supervisor { FactoryGirl.generate(:random_name) }
    keywords { FactoryGirl.generate(:random_string) }
    embargo { FactoryGirl.generate(:random_string) }
    language { FactoryGirl.generate(:random_string) }

    degree_name { FactoryGirl.generate(:random_string) }
    degree_level { FactoryGirl.generate(:random_string) }
    program { FactoryGirl.generate(:random_string) }

    committee { FactoryGirl.generate(:random_string) }
    abstract { FactoryGirl.generate(:random_string) }

    exam_date Date.today.next_month
    published_date 1.year.from_now

    # lac_license_agreed { true }
    # yspace_license_agreed { true }
    # etd_license_agreed { true }
    certify_content_correct { true }

    status Thesis::OPEN

    embargoed false
  end

end
