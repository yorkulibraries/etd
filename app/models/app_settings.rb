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
  field :student_supplementary_upload_files, default: '<p>File size must be limited to acceptable formats include:</p>
  <ul>
  <li><strong>Documents:</strong> Portable Document Format (.pdf), Text (.txt), Hypertext Markup Language (.html, .htm), Open Document Format (.odt, .odp, .ods).</li>
  <li><strong>Images:</strong> Portable Network Graphics format (.png), Tagged Image File format (.tif), JPEG (.jpg)</li>
  <li><strong>Data:</strong> Comma-separated values (.csv) or other delimited text, Extensible Markup Language (.xml)</li>
  <li><strong>Video:</strong> 8-10 bit uncompressed AVI (.avi)</li>
  <li><strong>Audio:</strong> Free Lossless Audio Codec or WAVE (.flac or .wav)</li>
  </ul>'
  field :student_review_license_info, default: 'Please review the licences below, you must agree to all to proceed.'
  field :student_review_license_lac, default: 'LAC Licence is required. Please download the form (<a href="~//lib/assets/lac-non-exclusive-licence-en.pdf">lac-non-exclusive-licence-en.pdf</a>), sign it and upload it.'
  field :student_review_lac_licence_instructions, default: '<p class="fw-bold">Please download, sign and upload the LAC Licence file. You must upload the licence to proceed to next step</p>
<ul>
  <li>Download English Licence: <a href="/documents/lac-non-exclusive-licence-en.pdf", target="_blank">LAC Non-Exclusive Licence (English)</a></p></li>
  <li>Download French Licence: <a href="/documents/lac-non-exclusive-licence-fr.pdf", target="_blank">LAC Non-Exclusive Licence (French)</a></li>
</ul>'
  field :student_review_license_yorkspace, default: ''
  field :student_review_license_etd, default: ''
  field :student_review_details, default: ''
  field :student_submit_for_review, default: ''
  field :student_check_status_description, default: ''
  field :student_check_status_open, default: 'A record has been created for you to submit your thesis/dissertation. As long as the status is Open, you may continue to make changes until you are ready to submit.'
  field :student_check_status_under_review, default: 'Your submission has been received and is being reviewed by a Thesis Coordinator in the Faculty of Graduate Studies. If you need to re-open your ETD record to make any changes, please email <a href="mailto:gsthesis@yorku.ca">gsthesis@yorku.ca</a>.'
  field :student_check_status_returned, default: 'Your submission has been reviewed by a Thesis Coordinator and has been returned to you for modification. Please make the updates detailed in the email from the Thesis Coordinator, attach an updated PDF (if applicable) and resubmit.'
  field :student_check_status_accepted, default: 'Your submission has been accepted and will be published following conferral of your degree.'
  field :student_check_status_published, default: 'Your thesis&#47;dissertation has been deposited in YorkSpace, York University&#39;s digital library and is available for electronic viewing through Library and Archives Canada.'
  field :student_check_status_rejected, default: 'Current status Rejected.'
end
