source 'http://rubygems.org'
ruby '3.1.2'
gem 'rack', '2.2.3.1'

gem 'rails', '~> 7.0', '>= 7.0.3'

## DATABASES ##
gem 'mysql2', '0.5.3', group: :production

## CSS AND JAVASCRIPT ##
gem 'coffee-rails', '~> 4.2'
gem 'jquery-rails' # "4.0.5"
gem 'jquery-tablesorter' # , "1.21.1"
gem 'jquery-ui-rails' # "5.0.5"
gem 'mini_racer', '~> 0.6.2'
gem 'sass-rails' # '~> 4.0.0'
gem 'uglifier' # , '>= 1.3.0'

## BOOTSTRAP && SIMPLE_FORM && CHOSEN ##
gem 'chosen-rails', '~> 1.10'
gem 'font-awesome-sass', '~> 6.1', '>= 6.1.1'
gem 'simple_form', '4.0.0'

## AUDITS ##
gem 'audited', '~> 5.0'

## APP SETTINGS ##
gem 'rails-settings-cached', '~> 2.8', '>= 2.8.2'

## EXCEPTION NOTIFICATIONS ##
gem 'exception_notification', '~> 4.4', '>= 4.4.1'

# SWORD API SUPPORT - Modified LCS version ##
gem 'sword2ruby', git: 'https://github.com/yorkulcs/sword2ruby.git'

## OTHER TOOLS AND UTILITIES ##
gem 'devise', '~> 4.8', '>= 4.8.1'
gem 'cancancan', '~> 3.4'
gem 'carrierwave', '~> 2.2', '>= 2.2.2'
gem 'json' # , '1.8.3'
gem 'kaminari' # , "0.17.0"
gem 'liquid' # , '3.0.6'
gem 'nokogiri' # , '1.6.7.2'
gem 'rexml', '~> 3.2', '>= 3.2.5'
gem 'rubyzip', '~> 1.2.2'
gem 'unicode' # , "0.4.4"
gem 'validates_timeliness', github: 'mitsuru/validates_timeliness', branch: 'rails7'

## EXEL EXPORT ##
gem 'axlsx', git: 'https://github.com/randym/axlsx.git'
gem 'axlsx_rails', '0.5.1'
gem 'roo' # , "1.13.2"
gem 'zip-zip', '~> 0.3'

## TESTING && DEVELOPMENT ##

group :development do
  gem 'bullet', '~> 7.0', '>= 7.0.2'
  gem 'nifty-generators', '0.4.6'
  gem 'populator', git: 'https://github.com/ryanb/populator.git'
  gem 'rack-livereload'
  gem 'web-console', '~> 2.0'
end

group :development, :test do
  gem 'guard-bundler', '~> 3.0'
  gem 'guard-livereload', require: false
  gem 'sqlite3'
end

group :test do
  gem 'byebug'
  gem 'capybara', '2.1.0'
  gem 'database_cleaner', '1.5.2'
  gem 'factory_girl_rails', '4.5.0'
  gem 'faker'
  gem 'guard-minitest', '2.4.6'
  gem 'minitest', '5.6.1'
  gem 'mocha', '0.14', require: false
  gem 'rails-controller-testing', '~> 1.0', '>= 1.0.5'
  gem 'shoulda-context'
  gem 'shoulda-matchers', '~> 5.1'
  gem 'spring' # , "1.3.6"
  gem 'webrat', '0.7.3'
end

gem 'puma'
