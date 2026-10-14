# frozen_string_literal: true

module GraduateOAuthFlow
  def ppy_login(user)
    host! '127.0.0.1:3210'
    headers = { 'HTTP_PYORK_USER' => user.username }
    headers['HTTP_PYORK_CYIN'] = user.sisid if user.is_a?(Student)
    get login_path, headers: headers
    assert_equal user.id, session[:user_id]
    assert_equal 'ppy', session[:auth_source]
  end

  def mock_provider(provider = 'google_oauth2', uid: 'stable-google-subject', email_verified: true, email: 'unrelated@example.com')
    raw = provider == 'google_oauth2' ? { 'email_verified' => email_verified } : {}
    OmniAuth.config.mock_auth[provider.to_sym] = OmniAuth::AuthHash.new(
      provider: provider, uid: uid, info: { email: email }, extra: { raw_info: raw },
      credentials: { token: 'NEVER_STORE_ACCESS_TOKEN', refresh_token: 'NEVER_STORE_REFRESH_TOKEN' }
    )
  end

  def csrf_token
    Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
  end

  def start_oauth(provider = 'google_oauth2', params: {})
    host! '127.0.0.1:3210'
    get graduate_login_path
    post graduate_auth_path(provider), params: params.merge(authenticity_token: csrf_token)
  end

  def complete_oauth(provider = 'google_oauth2', params: {})
    start_oauth(provider, params: params)
    assert_response :redirect
    follow_redirect! if response.location.include?('/callback')
  end

  def invite(student, approver: create(:user, role: User::MANAGER), provider: 'google_oauth2')
    ppy_login(approver)
    get staff_student_graduate_connections_path(student)
    post student_graduate_invitations_path(student), params: {
      authenticity_token: csrf_token, identity_verified: '1', provider: provider
    }
    assert_response :success
    url = Nokogiri::HTML(response.body).at_css('[data-invitation-url]')['value']
    [GraduateAuthenticationInvitation.order(:id).last, url]
  end

  def fresh_browser
    reset!
  end

  def enter_invitation(url)
    host! '127.0.0.1:3210'
    get URI.parse(url).request_uri
    assert_redirected_to graduate_login_path
    assert_equal 'no-store', response.headers['Cache-Control']
    assert_equal 'no-referrer', response.headers['Referrer-Policy']
    follow_redirect!
    assert_response :success
    assert_nil session[:user_id]
  end
end
