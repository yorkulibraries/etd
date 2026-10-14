# frozen_string_literal: true

# Fake, local-only credentials. Never contact providers during these tests.
ENV['GRADUATE_OAUTH_ENABLED'] = 'true'
ENV['GRADUATE_OAUTH_BASE_URL'] = "http://127.0.0.1:#{ENV.fetch('ETD_SYSTEM_TEST_PORT', '3210')}"
ENV['GOOGLE_CLIENT_ID'] = 'graduate-test-google'
ENV['GOOGLE_CLIENT_SECRET'] = 'graduate-test-google-secret'
