## GENERAL


if ActiveRecord::Base.connection.data_source_exists? 'settings'
  ## General Settings
  AppSettings.save_default(:app_name, "ETD")
  AppSettings.save_default(:app_owner, "York University Libraries")

  ## Maintenance Notice
  AppSettings.save_default(:app_maintenance, false)
  AppSettings.save_default(:app_maintenance_message, "ETD Application will be taken down for maintenance today from 12pm to 1pm.  We appologize for any inconvenience this may have caused.")


  ## Error Handling
  AppSettings.save_default(:errors_email_subject_prefix, "[ETD Error] ")
  AppSettings.save_default(:errors_email_from, "'ETD Notifier' <etd-errors@your-instituttion.website>")
  AppSettings.save_default(:errors_email_to, ["your.email@your-instituttion.email"])

  ## Notifications & Email

  AppSettings.save_default(:email_allow, true)
  AppSettings.save_default(:email_from,  "noreply@yorku.ca")

  AppSettings.save_default(:email_welcome_allow, true)
  AppSettings.save_default(:email_welcome_subject,  "Welcome to York University's Electronic Thesis and Dissertation (ETD) application")
  AppSettings.save_default(:email_welcome_body,  "Welcome email text goes here")

  AppSettings.save_default(:email_status_change_allow, true)
  AppSettings.save_default(:email_status_change_subject,  "The status of your thesis has been changed.")
  AppSettings.save_default(:email_status_change_body,  "Status Change email text goes here")

end
