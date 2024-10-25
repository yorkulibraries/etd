# frozen_string_literal: true

# RailsSettings Model
class AppSettings < RailsSettings::Base
  cache_prefix { 'v1' }

  field :app_name
  field :app_owner
  field :app_maintenance
  field :app_maintenance_message
  field :email_allow
  field :email_from
  field :email_welcome_subject
  field :email_welcome_allow
  field :email_welcome_body
  field :email_status_change_allow
  field :email_status_change_subject
  field :email_status_change_body
  field :errors_email_subject_prefix
  field :errors_email_from
  field :errors_email_to
  field :dspace_live_username
  field :dspace_live_password
  field :dspace_live_service_document_url
  field :dspace_live_collection_uri
  field :dspace_live_collection_title
  field :student_begin_submission
  field :student_begin_external_non_yorku_email
  field :student_update_details_initial
  field :student_update_details_abstract
  field :student_update_details_subjects
  field :student_update_details_keywords
  field :student_upload_files
  field :student_primary_upload_files
  field :student_supplementary_upload_files
  field :student_supplementary_embargo_upload_files
  field :student_review_license_info
  field :student_review_license_lac
  field :student_review_lac_licence_instructions
  field :student_review_license_yorkspace
  field :student_review_license_etd
  field :student_review_details
  field :student_submit_for_review
  field :student_check_status_description
  field :student_check_status_open
  field :student_check_status_under_review
  field :student_check_status_returned
  field :student_check_status_accepted
  field :student_check_status_published
  field :student_check_status_rejected
  field :primary_thesis_file_extensions
  field :supplemental_thesis_file_extensions
  field :licence_file_extensions
  field :embargo_file_extensions
end
