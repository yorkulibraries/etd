source 'http://rubygems.org'

gem 'rack', '2.0.9'

gem 'rails', '6.1'

## DATABASES ##
gem 'mysql2', '0.5.3', group: :production

## CSS AND JAVASCRIPT ##
gem 'coffee-rails', '~> 4.2'
gem 'jquery-rails' # "4.0.5"
gem 'jquery-tablesorter' # , "1.21.1"
gem 'jquery-ui-rails' # "5.0.5"
gem 'sass-rails' # '~> 4.0.0'
gem 'therubyracer', platforms: :ruby
gem 'uglifier' # , '>= 1.3.0'

## BOOTSTRAP && SIMPLE_FORM && CHOSEN ##
gem 'chosen-rails', '1.8.7'
gem 'font-awesome-sass', '~> 5.13.0'
gem 'less-rails'
gem 'simple_form' # , "3.2.1"
gem 'twitter-bootstrap-rails', '2.2.8'

## AUDITS ##
gem 'audited', '~> 4.7'

## APP SETTINGS ##
gem 'rails-settings-cached', '~> 0.5.0'

## EXCEPTION NOTIFICATIONS ##
gem 'exception_notification', '~> 4.4', '>= 4.4.1'

# SWORD API SUPPORT - Modified LCS version ##
gem 'sword2ruby', git: 'https://github.com/yorkulcs/sword2ruby.git'

## OTHER TOOLS AND UTILITIES ##
gem 'json' # , '1.8.3'
gem 'kaminari' # , "0.17.0"
gem 'nokogiri' # , '1.6.7.2'
# gem "cancan", "1.6.10"
gem 'cancancan', '1.16.0'
gem 'carrierwave', '1.3.1'
gem 'liquid' # , '3.0.6'
gem 'rubyzip', '~> 1.2.2'
gem 'unicode' # , "0.4.4"
gem 'validates_timeliness', '4.0.2'

## EXEL EXPORT ##
gem 'axlsx' # , "2.0.0"
gem 'axlsx_rails' # , "0.1.5"
gem 'roo' # , "1.13.2"
gem 'zip-zip', '0.3'

## TESTING && DEVELOPMENT ##

group :development do
  gem 'bullet', '5.2.0' # Testing SQL queries
  gem 'faker'
  gem 'guard-livereload', require: false
  gem 'mailcatcher' # FOR TESTING MAIL. Run mailcatcher, then go to localhost:1080
  gem 'nifty-generators', '0.4.6'
  gem 'populator', git: 'https://github.com/ryanb/populator.git'
  gem 'rack-livereload'
  gem 'web-console', '~> 2.0'
end

group :development, :test do
  gem 'sqlite3'
end

group :test do
  gem 'capybara', '2.1.0'
  gem 'database_cleaner', '1.5.2'
  gem 'factory_girl_rails', '4.5.0'
  gem 'guard-minitest', '2.4.4'
  gem 'minitest', '5.6.1'
  gem 'mocha', '0.14', require: false
  gem 'rails-controller-testing', '~> 1.0', '>= 1.0.5'
  gem 'ruby-prof'
  gem 'shoulda' # , "3.5"
  gem 'shoulda-context'
  gem 'shoulda-matchers'
  gem 'spring' # , "1.3.6"
  gem 'webrat', '0.7.3'
end

gem 'puma'
