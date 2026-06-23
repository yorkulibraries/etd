# frozen_string_literal: true

FactoryBot.define do
  factory :thesis do
    gem_record_event_id { FactoryBot.generate(:random_seqgradevent) }

    title { FactoryBot.generate(:random_string) }
    association :student, factory: :student, strategy: :create
    assigned_to { nil }

    author { FactoryBot.generate(:random_name) }
    supervisor { FactoryBot.generate(:random_name) }
    keywords { FactoryBot.generate(:random_string) }
    embargo { FactoryBot.generate(:random_string) }
    language { FactoryBot.generate(:random_string) }

    degree_name { FactoryBot.generate(:random_string) }
    degree_level { FactoryBot.generate(:random_string) }
    program { FactoryBot.generate(:random_string) }

    committee { FactoryBot.generate(:random_string) }
    abstract { FactoryBot.generate(:random_string) }

    exam_date { Date.today.next_month }
    published_date { 1.year.from_now }

    # lac_license_agreed { true }
    # yspace_license_agreed { true }
    # etd_license_agreed { true }
    certify_content_correct { true }

    status { Thesis::OPEN }

    embargoed { false }
  end

end
