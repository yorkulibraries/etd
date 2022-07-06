class AppSettings < RailsSettings::CachedSettings
  source Rails.root.join("config/app.yml")
  attr_accessible :var
end
