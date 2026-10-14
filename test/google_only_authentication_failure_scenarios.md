# Google-only graduate sign-in failure scenarios

Written before removing Facebook from the application. Keep Google UID linking,
PKCE, nonce, verified-email claims, CSRF, single-use invitations, blocked-user
checks, Passport York and staff support unchanged. Do not save the Google email
or delete existing records.

- Facebook must not appear in configured providers, login buttons, connection
  settings, or the staff invitation selector, even if old credentials remain.
- A POST to Facebook initiation or a Facebook callback must fail without an
  identity, student session, or provider network exchange.
- Staff cannot create a Facebook invitation. An older Facebook invitation must
  remain unconsumed and cannot establish enrollment intent.
- Persisted Facebook identities and invitations must not break student/staff
  pages after removing the provider label. They must stay out of the UI.
- A new Google invitation must still work when older Facebook invitations exist.
- An already-issued Facebook graduate cookie must lose private-page access,
  clear its authentication data, and revoke its server session.
- A Facebook identity cannot receive a fresh graduate session token.
- Google linking and returning sign-in must retain the existing student email.

HTTP checks run through Rails routes, forms, CSRF, encrypted session cookies and
the existing mocked provider boundary. Browser checks cover desktop/mobile
login, student connections, staff invitations and Google enrollment, saving
screenshots under `tmp/graduate-authentication/screenshots/`. The verification
runner records repeatable commands and results. No live provider calls, email,
deployment, commits or pushes are part of this verification.
