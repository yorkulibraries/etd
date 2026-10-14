# frozen_string_literal: true

require 'uri'
require 'digest'

# Only the supported provider subject may be used. Email is never an account key.
module GraduateAuthentication
  PROVIDERS = %w[google_oauth2].freeze
  INTENT_LIFETIME = 10.minutes
  FAILURE_MESSAGE = 'We could not complete graduate sign-in. Please try again. If your account is not connected, contact FGS for help.'
  class Rejected < StandardError; end

  # Only the registered web-server code flow is accepted. The upstream Google
  # strategy also supports direct tokens, JSON and postmessage flows.
  class GoogleStrategy < OmniAuth::Strategies::GoogleOauth2
    option :name, 'google_oauth2'

    def authorize_params
      super.tap do |params|
        session['graduate.google_nonce'] = SecureRandom.hex(32)
        params[:nonce] = session['graduate.google_nonce']
      end
    end

    private

    def get_access_token(request)
      unless GraduateAuthentication.authorization_code_callback?(request)
        raise CallbackError.new(:invalid_credentials, 'Web authorization code required')
      end
      nonce = session.delete('graduate.google_nonce')
      verifier = session['omniauth.pkce.verifier']
      unless nonce.is_a?(String) && nonce.match?(/\A[0-9a-f]{64}\z/) &&
             verifier.is_a?(String) && verifier.match?(/\A[0-9a-f]{128}\z/)
        raise CallbackError.new(:invalid_credentials, 'Missing transaction binding')
      end

      token = client_get_token(request.params['code'], callback_url)
      id_token = token['id_token']
      unless id_token.is_a?(String) && id_token.present?
        raise CallbackError.new(:invalid_credentials, 'Missing identity token')
      end
      claims = id_token_claims(id_token)
      unless claims['nonce'].is_a?(String) && secure_compare(claims['nonce'], nonce)
        raise CallbackError.new(:invalid_credentials, 'Invalid transaction binding')
      end
      @raw_info = token.get(USER_INFO_URL).parsed
      unless @raw_info.is_a?(Hash) && claims['sub'].is_a?(String) &&
             claims['sub'].present? && claims['sub'] == @raw_info['sub']
        raise CallbackError.new(:invalid_credentials, 'Identity subject mismatch')
      end
      token
    rescue JWT::DecodeError, JWT::VerificationError
      raise CallbackError.new(:invalid_credentials, 'Invalid identity token')
    end
  end

  class SafeLogger
    %i[debug info warn error fatal].each do |level|
      define_method(level) { |*_args| Rails.logger.public_send(level, 'Graduate OAuth middleware event.') }
    end
  end

  class << self
    attr_reader :base_url, :provider_credentials

    def configure!
      @base_url = validated_base_url(ENV['GRADUATE_OAUTH_BASE_URL'])
      @provider_credentials = {}
      return unless ENV['GRADUATE_OAUTH_ENABLED'] == 'true' && @base_url

      {
        'google_oauth2' => [ENV['GOOGLE_CLIENT_ID'], ENV['GOOGLE_CLIENT_SECRET']]
      }.each do |provider, credentials|
        next unless credentials.all?(&:present?)
        @provider_credentials[provider] = credentials.freeze
      end
      @provider_credentials.freeze
    end

    def enabled_providers
      provider_credentials.keys
    end

    def label(provider)
      { 'google_oauth2' => 'Google' }.fetch(provider)
    end

    def callback_url(provider)
      "#{base_url}/graduate/auth/#{provider}/callback"
    end

    def authorization_code_callback?(request)
      code = request.params['code']
      request.get? && code.is_a?(String) && code.present? && code == code.strip &&
        %w[access_token id_token redirect_uri].none? { |key| request.params.key?(key) }
    end

    def clear_transaction!(session)
      %w[omniauth.state omniauth.pkce.verifier graduate.google_nonce].each { |key| session.delete(key) }
    end

    def active_student?(user)
      user.is_a?(Student) && user.role == User::STUDENT && user.active?
    end

    def staff_authorized?(user)
      user.present? && user.active? && [User::ADMIN, User::MANAGER].include?(user.role)
    end

    def ppy_student_session?(session, user)
      active_student?(user) && session[:auth_source] == 'ppy' &&
        session[:user_id] == user.id && session[:return_to_user_id].blank?
    end

    # Runs after the Rails CSRF verifier, inside the strategy request phase.
    # All modes and targets come from signed session state, never request params.
    def prepare_intent!(env)
      session = env.fetch('rack.session')
      provider = env.fetch('omniauth.strategy').name
      raise Rejected unless enabled_providers.include?(provider)

      clear_transaction!(session)

      user = User.find_by(id: session[:user_id]) if session[:user_id]
      if GraduateSession.marked?(session)
        valid_session = session[:auth_source] == 'graduate_oauth' && session[:return_to_user_id].blank? &&
                        active_student?(user) &&
                        GraduateSession.valid_for?(session[:graduate_session_token],
                                                   identity_id: session[:graduate_identity_id], student_id: user.id)
        unless valid_session
          GraduateSession.revoke(session[:graduate_session_token])
          env['warden']&.logout
          session.clear
          user = nil
        end
      end
      intent = { 'provider' => provider, 'expires_at' => INTENT_LIFETIME.from_now.to_i }
      enrollment = session[:graduate_enrollment]
      if enrollment
        invitation = GraduateAuthenticationInvitation.find_by(id: enrollment['invitation_id'])
        raise Rejected unless enrollment['expires_at'].to_i > Time.current.to_i &&
                              invitation&.usable? && invitation.provider == provider
        intent.merge!('mode' => 'invitation', 'invitation_id' => invitation.id)
      elsif ppy_student_session?(session, user)
        intent.merge!('mode' => 'link', 'student_id' => user.id)
      elsif user && (!active_student?(user) || session[:return_to_user_id].present?)
        raise Rejected
      else
        intent['mode'] = 'login'
      end
      session[:graduate_oauth_intent] = intent
    end

    def verified_subject!(env, provider)
      strategy = env['omniauth.strategy']
      auth = env['omniauth.auth']
      raise Rejected unless enabled_providers.include?(provider) && strategy.is_a?(OmniAuth::Strategies::GoogleOauth2) &&
                            strategy.name == provider && auth.is_a?(OmniAuth::AuthHash) && auth.provider == provider
      uid = auth.uid
      raise Rejected unless uid.is_a?(String) && uid.present? && uid.length <= 191 && uid == uid.strip

      verified = auth.dig('extra', 'raw_info', 'email_verified')
      raise Rejected unless verified == true || verified == 'true'
      uid
    end

    private

    def validated_base_url(value)
      return if value.blank?

      uri = URI.parse(value)
      return unless uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? &&
                    ['', '/'].include?(uri.path)
      return unless uri.scheme == 'https' || (!Rails.env.production? && uri.scheme == 'http' &&
                                              %w[localhost 127.0.0.1].include?(uri.host))

      value.delete_suffix('/')
    rescue URI::InvalidURIError
      nil
    end
  end
end
