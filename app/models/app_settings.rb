# RailsSettings Model
class AppSettings < RailsSettings::Base
  cache_prefix { "v1" }

  field :app_name, default: (ENV["app_name"] || "ETD")
  field :app_owner, default: (ENV["app_owner"] || "York University Libraries")
  field :app_maintenance, default: (ENV["app_maintenance"] || false)
  field :app_maintenance_message, default: (ENV["app_maintenance_message"] || "ETD Application will be taken down for maintenance today from 12pm to 1pm.  We appologize for any inconvenience this may have caused.")
  field :email_allow, default: (ENV["email_allow"] || true)
  field :email_from, default: (ENV["email_from"] || "noreply@library.yorku.ca")
  field :email_welcome_subject, default: (ENV["email_welcome_subject"] || "Welcome to York University's Electronic Thesis and Dissertation (ETD) application")
  field :email_welcome_allow, default: (ENV["email_welcome_allow"] || true)
  field :email_welcome_body, default: (ENV["email_welcome_body"] || "Email body")
  field :email_status_change_allow, default: (ENV["email_status_change_allow"] || true)
  field :email_status_change_subject, default: (ENV["email_status_change_subject"] || "The status of your thesis has been changed.")
  field :email_status_change_body, default: (ENV["email_status_change_body"] || "Status Change email text goes here")
  field :errors_email_subject_prefix, default: (ENV["errors_email_subject_prefix"] || "[ETD Error] ")
  field :errors_email_from, default: (ENV["errors_email_from"] || "'ETD Notifier' <etd-errors@your-instituttion.website>")
  field :errors_email_to, default: (ENV["errors_email_to"] || "your.email@your-instituttion.email")
end
