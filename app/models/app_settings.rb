class AppSettings < RailsSettings::Base
	source Rails.root.join("config/app.yml")
	attr_accessible :var

end
