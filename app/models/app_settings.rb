# frozen_string_literal: true

# RailsSettings Model
class AppSettings < RailsSettings::Base
  cache_prefix { 'v1' }

  field :app_name, default: ENV['app_name'] || 'ETD'
  field :app_owner, default: ENV['app_owner'] || 'York University Libraries'
  field :app_maintenance, default: ENV['app_maintenance'] || false
  field :app_maintenance_message,
        default: ENV['app_maintenance_message'] || 'ETD Application will be taken down for maintenance today from 12pm to 1pm.  We apologize for any inconvenience this may have caused.'
  field :email_allow, default: ENV['email_allow'] || true
  field :email_from, default: ENV['email_from'] || 'noreply@yorku.ca'
  field :email_welcome_subject,
        default: ENV['email_welcome_subject'] || "Welcome to York University's Electronic Thesis and Dissertation (ETD) application"
  field :email_welcome_allow, default: ENV['email_welcome_allow'] || true
  field :email_welcome_body, default: ENV['email_welcome_body'] || 'Email body'
  field :email_status_change_allow, default: ENV['email_status_change_allow'] || true
  field :email_status_change_subject,
        default: ENV['email_status_change_subject'] || 'The status of your thesis has been changed.'
  field :email_status_change_body, default: ENV['email_status_change_body'] || 'Status Change email text goes here'
  field :errors_email_subject_prefix, default: ENV['errors_email_subject_prefix'] || '[ETD Error] '
  field :errors_email_from,
        default: ENV['errors_email_from'] || "'ETD Notifier' <etd-errors@your-instituttion.website>"
  field :errors_email_to, default: ENV['errors_email_to'] || 'your.email@your-instituttion.email'
  field :dspace_live_username, default: ENV['dspace_live_username'] || ''
  field :dspace_live_password, default: ENV['dspace_live_password'] || ''
  field :dspace_live_service_document_url, default: ENV['dspace_live_service_document_url'] || ''
  field :dspace_live_collection_uri, default: ENV['dspace_live_collection_uri'] || ''
  field :dspace_live_collection_title, default: ENV['dspace_live_collection_title'] || ''
  field :student_begin_submission, default: ''
  field :student_begin_external_non_yorku_email, default: ''
  field :student_update_details_initial, default: ''
  field :student_update_details_abstract, default: ''
  field :student_update_details_subjects, default: ''
  field :student_update_details_keywords, default: ''
  field :student_upload_files, default: ''
  field :student_review_details, default: ''
  field :student_submit_for_review, default: ''
  field :student_submit_for_review_license_lac, default: ''
  field :student_submit_for_review_license_yorkspace, default: ''
  field :student_submit_for_review_license_etd, default: ''
  field :student_check_status, default: ''
end
