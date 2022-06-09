source 'http://rubygems.org'

gem "rack", "2.0.9"

gem 'rails', '5.0.7.2'
gem 'rails-controller-testing'

## DATABASES ##
gem 'mysql2', '0.5.3'
gem 'sqlite3', '~> 1.3.13'

## CSS AND JAVASCRIPT ##
gem 'sass-rails' #'~> 4.0.0'
gem 'uglifier' #, '>= 1.3.0'
gem 'coffee-rails' #, '~> 4.1.0'
gem 'therubyracer', platforms: :ruby
gem 'jquery-rails' #"4.0.5"
gem 'jquery-ui-rails'# "5.0.5"
gem 'jquery-tablesorter' #, "1.21.1"

## BOOTSTRAP && SIMPLE_FORM && CHOSEN ##
gem 'chosen-rails', "1.8.7"
gem "less-rails"
gem 'twitter-bootstrap-rails', "2.2.8"
gem "simple_form" #, "3.2.1"
gem "font-awesome-rails", "4.6.3.1"

## AUDITS ##
#gem "audited-activerecord" #, "4.2"
gem "audited" , "~> 4.7"

## APP SETTINGS ##
gem "rails-settings-cached" #, "0.4.1"

## EXCEPTION NOTIFICATIONS ##
gem 'exception_notification', "4.2.0"

# SWORD API SUPPORT - Modified LCS version ##
gem "sword2ruby", git: "https://github.com/yorkulcs/sword2ruby.git"

## OTHER TOOLS AND UTILITIES ##
gem 'json' #, '1.8.3'
gem 'nokogiri' #, '1.6.7.2'
gem "kaminari" #, "0.17.0"
#gem "cancan", "1.6.10"
gem "cancancan", "1.16.0"
gem "carrierwave", "1.3.1"
gem 'validates_timeliness', '4.0.2'
gem 'rubyzip'#, "0.9.9"
gem "unicode"#, "0.4.4"
gem 'liquid'#, '3.0.6'

## EXEL EXPORT ##
gem "roo" #, "1.13.2"
gem "axlsx" #, "2.0.0"
gem 'axlsx_rails'#, "0.1.5"
gem 'zip-zip', "0.3"

## TESTING && DEVELOPMENT ##

group :development do
	gem 'guard-livereload', require: false
	gem "rack-livereload"

  gem 'nifty-generators', "0.4.6"
	gem "populator", git: "https://github.com/ryanb/populator.git"
	gem "faker"
  gem "bullet", "5.2.0" # Testing SQL queries
	gem "mailcatcher" # FOR TESTING MAIL. Run mailcatcher, then go to localhost:1080

	gem 'web-console', '~> 2.0'
end

group :test do
	gem "minitest", "5.6.1"
  gem 'webrat', "0.7.3"
  gem 'factory_girl_rails', "4.5.0"
  gem 'shoulda'#, "3.5"
  gem 'shoulda-matchers'
  gem 'shoulda-context'
  gem "mocha", "0.14", require: false
  gem "capybara", "2.1.0"
  gem 'database_cleaner', "1.5.2"
  gem "guard-minitest", "2.4.4"
  gem 'spring' #, "1.3.6"
  gem "ruby-prof"
end

gem 'puma'
