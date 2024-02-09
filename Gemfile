# frozen_string_literal: true

source 'http://rubygems.org'
ruby '3.1.2'

gem 'puma', '~> 6.4', '>= 6.4.2'
gem 'rails', '~> 7.0', '>= 7.0.3.1'

## DATABASES ##
gem 'mysql2', '0.5.3'

## CSS AND JAVASCRIPT ##
gem 'coffee-rails', '~> 4.2'
gem 'jquery-rails', '4.5.0'
gem 'jquery-tablesorter', '~> 1.27', '>= 1.27.2'
gem 'jquery-ui-rails', '6.0.1'
gem 'sass-rails', '~> 6.0'
gem 'actiontext', '~> 7.0', '>= 7.0.3.1'
gem 'trix-rails', require: 'trix'
gem 'terser', '~> 1.1', '>= 1.1.20'
source 'https://rails-assets.org' do
  gem 'rails-assets-chosen-bootstrap-theme'
end

## BOOTSTRAP && SIMPLE_FORM && CHOSEN ##
gem 'active_link_to', '~> 1.0', '>= 1.0.5'
gem 'bootstrap', '~> 5.3', '>= 5.3.2'
gem 'chosen-rails', '~> 1.10'
gem 'font-awesome-rails', '~> 4.7'
gem 'simple_form', '~> 5.3'

## AUDITS ##
gem 'audited', '~> 5.0', '>= 5.0.2'

## APP SETTINGS ##
gem 'rails-settings-cached', '~> 2.8', '>= 2.8.2'

## EXCEPTION NOTIFICATIONS ##
gem 'exception_notification', '~> 4.5'

# SWORD API SUPPORT - Modified LCS version ##
gem 'sword2ruby', git: 'https://github.com/yorkulcs/sword2ruby.git'

## OTHER TOOLS AND UTILITIES ##
gem 'cancancan', '~> 3.4'
gem 'carrierwave', '~> 2.2', '>= 2.2.2'
gem 'devise', '~> 4.8', '>= 4.8.1'
gem 'kaminari', '~> 1.2', '>= 1.2.2'
gem 'liquid', '~> 5.4'
gem 'nokogiri', '~> 1.13', '>= 1.13.8'
gem 'rexml', '~> 3.2', '>= 3.2.5'
gem 'rubyzip', '~> 1.3.0'
gem 'unicode', '~> 0.4.4.4'
gem 'validates_timeliness', github: 'mitsuru/validates_timeliness', branch: 'rails7'

## EXEL EXPORT ##
gem 'caxlsx', '3.2.0'
gem 'caxlsx_rails', '0.6.3'
gem 'roo', '~> 2.9'
gem 'zip-zip', '~> 0.3'

## TESTING && DEVELOPMENT ##

group :development do
  gem 'web-console', '~> 4.2'
end

group :development, :test do
  gem 'faker', '~> 2.22'
  gem 'guard-bundler', '~> 3.0'
  gem 'guard-livereload', '~> 2.5', '>= 2.5.2', require: false
  gem 'populator', git: 'https://github.com/ryanb/populator.git'
end

group :test do
  gem 'byebug', '~> 11.1', '>= 11.1.3'
  gem 'capybara', '~> 3.39', '>= 3.39.2'
  gem 'database_cleaner-active_record'
  gem 'factory_girl_rails', '4.8.0'
  gem 'guard-minitest', '2.4.6'
  gem 'minitest', '~> 5.20'
  gem 'mocha', '~> 2.1'
  gem 'rails-controller-testing', '~> 1.0', '>= 1.0.5'
  gem 'selenium-webdriver', '~> 4.15'
  gem 'shoulda-context', '~> 2.0'
  gem 'shoulda-matchers', '~> 5.1'
  gem 'spring' # , "1.3.6"
end
