FactoryGirl.define do
  factory :export_log do
    association :creator, factory: :user

    published_date 2.months.ago
    production_export false
    complete_thesis false
    publish_thesis false

    theses_count 0
    failed_count 0
    successful_count 0

    theses_ids ''
    failed_ids ''
    successful_ids ''

    output_full ''
    output_error ''

    job_id ''
    job_status ExportLog::JOB_OPEN
    job_started_at nil
    job_completed_at nil
    job_cancelled_at nil
    job_cancelled_by_id nil
  end
end
