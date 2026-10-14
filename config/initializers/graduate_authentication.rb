# frozen_string_literal: true

require Rails.root.join('app/services/graduate_authentication')

GraduateAuthentication.configure!
OmniAuth.config.path_prefix = '/graduate/auth'
OmniAuth.config.allowed_request_methods = [:post]
OmniAuth.config.logger = GraduateAuthentication::SafeLogger.new
OmniAuth.config.before_request_phase = ->(env) { GraduateAuthentication.prepare_intent!(env) }
OmniAuth.config.on_failure = lambda do |env|
  GraduateAuthentication.clear_transaction!(env['rack.session']) if env['rack.session']
  env['rack.session']&.delete(:graduate_oauth_intent)
  env['rack.session']&.delete(:graduate_enrollment)
  [302, { 'Location' => '/graduate/auth/failure', 'Content-Type' => 'text/html' }, []]
end

Rails.application.config.middleware.use OmniAuth::Builder do
  GraduateAuthentication.enabled_providers.each do |name|
    credentials = GraduateAuthentication.provider_credentials.fetch(name)
    options = { callback_url: GraduateAuthentication.callback_url(name) }
    # Google uses redirect_uri (not callback_url) and permits request overrides
    # by default. Keep callback, scopes, access type and state server controlled.
    options.merge!(redirect_uri: GraduateAuthentication.callback_url(name), scope: 'openid,email,profile',
                   access_type: 'online', prompt: 'select_account', overridable_authorize_options: [], pkce: true)
    provider GraduateAuthentication::GoogleStrategy, *credentials, **options
  end
end
