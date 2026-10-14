# frozen_string_literal: true

# Written before the provider correction. Exercise actual OmniAuth middleware;
# mock only the provider's token and user-info boundary, without network calls.
# Failure cases: missing PKCE/nonce, caller overrides, alternate callback
# credentials, mismatched nonce/subject, missing or invalid ID token, and
# cancellation leaving stale transaction secrets.
require_relative '../support/graduate_oauth_environment'
require 'test_helper'
require_relative '../support/graduate_oauth_flow'

class GraduateOAuthTransactionTest < ActionDispatch::IntegrationTest
  include GraduateOAuthFlow

  setup do
    host! '127.0.0.1:3210'
    @student = create(:student)
    @forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    OmniAuth.config.test_mode = false
    ppy_login(@student)
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.clear
    Warden.test_reset!
  end

  test 'Google initiates fresh S256 and nonce with server controlled options' do
    first = google_request(params: { nonce: 'caller', code_challenge: 'caller', code_challenge_method: 'plain' })
    verifier = session['omniauth.pkce.verifier']
    assert verifier.is_a?(String) && verifier.length >= 43
    assert_equal ['S256'], first['code_challenge_method']
    assert_equal [Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)], first['code_challenge']
    assert_match(/\A[0-9a-f]{64}\z/, first['nonce'].first)
    assert_not_equal ['caller'], first['nonce']
    second = google_request
    assert_not_equal first['nonce'], second['nonce']
    assert_not_equal first['code_challenge'], second['code_challenge']
  end

  test 'Google completes code exchange with canonical callback PKCE nonce and same subject' do
    query = google_request
    stub_google_exchange(query)
    assert_difference('GraduateIdentity.count', 1) { google_callback(query) }
    assert_equal @student.id, session[:user_id]
    assert_equal 'ppy', session[:auth_source]
    assert_nil session['omniauth.pkce.verifier']
    assert_nil session['graduate.google_nonce']
    assert_nil session[:graduate_oauth_intent]
  end

  test 'Google rejects mismatched or missing nonce and ID token' do
    [:wrong_nonce, :missing_nonce, :missing_token, :invalid_token, :wrong_subject, :wrong_audience, :wrong_issuer, :expired].each do |failure|
      query = google_request
      stub_google_exchange(query, failure: failure)
      assert_no_difference('GraduateIdentity.count', failure.to_s) { google_callback(query) }
      assert_nil session['omniauth.pkce.verifier']
      assert_nil session['graduate.google_nonce']
      assert_nil session[:graduate_oauth_intent]
    end
  end

  test 'Google rejects callback credential and redirect alternatives before exchange' do
    %w[google_oauth2].each do |provider|
      [ { access_token: 'synthetic' }, { code: '' }, { code: ['a', 'b'] },
        { code: 'synthetic', access_token: 'synthetic' },
        { code: 'synthetic', id_token: 'synthetic' },
        { code: 'synthetic', redirect_uri: 'https://example.invalid/callback' } ].each do |input|
        start_oauth(provider)
        query = CGI.parse(URI.parse(response.location).query)
        OAuth2::Strategy::AuthCode.any_instance.expects(:get_token).never
        assert_no_difference('GraduateIdentity.count') do
          get graduate_auth_callback_path(provider), params: input.merge(state: query['state'].first)
        end
        assert_response :redirect
        assert_nil session[:graduate_oauth_intent]
      end
    end
  end

  test 'Google cancellation and removed provider requests clear transaction secrets' do
    query = google_request
    get graduate_auth_callback_path('google_oauth2'), params: { error: 'access_denied', state: query['state'].first }
    assert_nil session['omniauth.pkce.verifier']
    assert_nil session['graduate.google_nonce']
    assert_nil session[:graduate_oauth_intent]
    google_request
    start_oauth('facebook')
    assert_response :not_found
    assert_nil session['omniauth.pkce.verifier']
    assert_nil session['graduate.google_nonce']
  end

  private

  def google_request(params: {})
    start_oauth('google_oauth2', params: params)
    assert_response :redirect
    CGI.parse(URI.parse(response.location).query)
  end

  def google_callback(query)
    get graduate_auth_callback_path('google_oauth2'), params: { code: 'synthetic-code', state: query['state'].first }
  end

  def stub_google_exchange(query, failure: nil)
    claims = { 'iss' => 'https://accounts.google.com', 'aud' => ENV['GOOGLE_CLIENT_ID'],
               'sub' => 'transaction-google-subject', 'exp' => 1.hour.from_now.to_i, 'nonce' => query['nonce'].first }
    claims['nonce'] = 'different' if failure == :wrong_nonce
    claims.delete('nonce') if failure == :missing_nonce
    claims['sub'] = 'different' if failure == :wrong_subject
    claims['aud'] = 'different' if failure == :wrong_audience
    claims['iss'] = 'https://example.invalid' if failure == :wrong_issuer
    claims['exp'] = 2.hours.ago.to_i if failure == :expired
    # Synthetic token returned at the mocked HTTPS token-endpoint boundary.
    id_token = JWT.encode(claims, nil, 'none')
    id_token = nil if failure == :missing_token
    id_token = 'invalid' if failure == :invalid_token
    client = OAuth2::Client.new(ENV['GOOGLE_CLIENT_ID'], ENV['GOOGLE_CLIENT_SECRET'])
    token = OAuth2::AccessToken.from_hash(client, 'access_token' => 'synthetic-token',
                                       'expires_in' => 3600, 'id_token' => id_token)
    info = { 'sub' => 'transaction-google-subject', 'email_verified' => true, 'email' => 'synthetic@example.invalid' }
    token.stubs(:get).with(OmniAuth::Strategies::GoogleOauth2::USER_INFO_URL).returns(Struct.new(:parsed).new(info))
    OmniAuth::Strategies::GoogleOauth2.any_instance.stubs(:token_info).returns({ 'scope' => 'openid email profile' })
    expected_verifier = session['omniauth.pkce.verifier']
    assert expected_verifier.present?
    OAuth2::Strategy::AuthCode.any_instance.expects(:get_token).with(
      'synthetic-code',
      has_entries(redirect_uri: GraduateAuthentication.callback_url('google_oauth2'), code_verifier: expected_verifier),
      anything
    ).returns(token)
  end
end
