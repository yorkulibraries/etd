# Graduate sign-in setup

## Purpose

Let existing ETD students return using Google after they lose Passport York access. External sign-in connects to their existing student record and theses. It does not create a student account or change thesis editing or embargo permissions.

## Account linking

Graduate OAuth sessions now use a server-side session record with a fixed 12-hour lifetime. Signing out revokes that browser's session; signing in again rotates it. Blocking a student revokes all of their graduate sessions, including dormant browsers, and unblocking does not restore those sessions. Other independently signed-in browsers remain active until their own expiry or revocation. Only the session-token digest is stored in the database. Existing graduate OAuth cookies issued before the server-side session change require a fresh sign-in. Removed-provider identities and invitations remain stored but are hidden and cannot grant access. Their existing graduate sessions are rejected. Passport York and staff support keep their existing session behavior.

Google uses S256 PKCE and a fresh OpenID Connect nonce, which must match the returned identity token. ETD accepts only the registered server-side authorization-code callback. Callback credentials, redirects, and account targets cannot be supplied through an alternative token or JSON flow. Real provider consent and exchange still require staging verification. See [Google discovery metadata](https://accounts.google.com/.well-known/openid-configuration) and [Google OpenID Connect](https://developers.google.com/identity/openid-connect/openid-connect).

Students who still have Passport York access sign in normally and connect a personal Google account from their graduate sign-in settings. Each provider account belongs to exactly one student. Matching names or email addresses does not establish ownership.

For graduates who have lost Passport York access, an FGS administrator or manager verifies the graduate through an established university process, then prepares a short-lived linking invitation for the correct student record. The graduate opens that invitation and signs in with the chosen provider. The invitation is consumed only when linking succeeds. ETD does not automatically send the invitation.

An FGS invitation is an access credential. Share it only with the verified graduate through the approved channel. If the wrong provider account was linked, an administrator or manager must revoke it and repeat verification.

Blocked students cannot sign in directly or use linking invitations. Active staff can still use the existing student support view for a blocked record, but cannot connect a social account while impersonating a student. Student sessions cannot open staff reports, account lists, or other students' list and audit pages.

## Provider ownership

Use a university-managed Google Cloud application. Record who maintains the applications and their recovery arrangements. Use separate credentials and exact callback URLs for staging and production. Keep client secrets in the deployment secret store, not Git or messages.

The staging origin supplied for this task is `https://etdqa.library.yorku.ca`. Production needs its own confirmed origin and provider configuration.

## Google

1. Create a web application OAuth client in the university's Google Cloud project.
2. Configure the consent screen for the intended audience, including graduates using personal Google accounts. An organization-only audience would exclude those accounts.
3. Register the application's exact HTTPS callback URL, using the route documented in the implementation below.
4. Configure the client ID and secret on the server. Request only the identity information needed for sign-in.
5. Exercise the complete linking, logout, and return sign-in flow with a staging student before enabling production.

Google identifies an account by its stable subject identifier. An email address can change and must not be the account key. The Google email is not saved in the connection or used to update the student contact or external email. See [Google OpenID Connect](https://developers.google.com/identity/openid-connect/openid-connect) and [web application OAuth setup](https://developers.google.com/identity/protocols/oauth2/web-server).

## Server routing

The production web server's Passport York protection must allow the public graduate login, invitation, OAuth initiation, callback, and failure routes to reach Rails without forcing a Passport York challenge. Graduates must also be able to use their authenticated student pages without that challenge.

Allow the compiled `/assets/` files needed by the public sign-in screens, including styles, scripts, and York branding. This public asset access must remain separate from the private `/uploads/` directory.

Keep Passport York verification at its dedicated login route. Strip client-supplied Passport York identity headers at the edge and set trusted headers only after university authentication. All student and staff pages remain protected by application sessions and permissions even where Passport York is no longer required at the edge.

Use the configured canonical HTTPS origin for OAuth callbacks. Reverse-proxy forwarding must preserve the scheme, host, and session cookies. Set invitation pages to avoid caching and referrer leakage; redact invitation tokens and OAuth codes in proxy and application logs.

Uploaded files currently live under `public/uploads`. Apache must deny direct access to `/uploads/` before relaxing Passport York protection for the application. Use the application's authorized document download route instead. Publicly exposing the static upload directory would bypass student ownership checks. Confirm that neither Apache aliases nor another file server expose the same files through an alternative path.

Read-only requests to the staging root and `/login` on 2026-10-05 returned `403 Forbidden` from `Apache/2.4.58 (Ubuntu)` in this environment. This confirms Apache is present, but does not identify the Passport York rules or explain the access restriction. Inspect the staging virtual host and authentication configuration before changing it. The live configuration is not present in this repository, so this document cannot supply an exact Apache patch.

## Activation and verification

Keep the feature disabled until credentials, callbacks, server routing, and public provider access are ready. The local verification uses simulated provider responses and proves application behavior. Live provider consent and the production Passport York boundary need separate staging verification.

Verify Google sign-in, a student with existing Passport York access, a graduate invitation, invitation expiry/reuse, an unrelated social account, cancellation, blocked students, logout, and access to the existing thesis. Confirm students cannot view another student's record or gain staff permissions. Confirm published or accepted theses retain the existing edit restrictions.

Verify that authenticated owners can download their documents, while anonymous users and other students cannot. A direct `/uploads/` URL must be denied at the public Apache boundary and at the Rails boundary.

The separate student embargo-request workflow remains outside this authentication change. Adding an alternative sign-in does not enable graduates to directly change permanent embargoes.

## Implementation configuration and commands

Set these environment variables in the server's secret/configuration store, then restart the Rails application:

```dotenv
GRADUATE_OAUTH_ENABLED=true
GRADUATE_OAUTH_BASE_URL=https://etdqa.library.yorku.ca
GOOGLE_CLIENT_ID=<Google web client ID>
GOOGLE_CLIENT_SECRET=<Google web client secret>
```

The feature is disabled by default. A provider appears only when its ID and secret are present and the canonical origin is valid. Production requires HTTPS.

Register this exact staging callback URL:

| Provider | Authorized callback URL |
| --- | --- |
| Google | `https://etdqa.library.yorku.ca/graduate/auth/google_oauth2/callback` |

The public sign-in entry is `/graduate/login`. Provider initiation lives under `/graduate/auth/` and requires a POST with a valid CSRF token. The callback and failure endpoints must be reachable without Passport York authentication.

Install the bundle and apply both graduate-authentication and graduate-session migrations through the existing deployment process before enabling the feature. Restart the application after the schema and configuration are ready.

| Route | Purpose |
| --- | --- |
| `/graduate/login` | Public graduate sign-in |
| `/graduate/enroll?token=...` | One-time invitation entry; redirects to a clean URL |
| `/my/graduate-connections` | Student account connections |
| `/students/:student_id/graduate-connections` | FGS connection management and invitation form |
| `/students/:student_id/graduate-invitations` | FGS invitation creation by POST |

The repeatable verification runner uses a dedicated SQLite test database and synthetic provider responses:

```sh
docker exec etd-graduate-auth bash script/verify_graduate_authentication
```

The application image must contain the updated bundle and local Chromium/Chrome driver. The runner writes `tmp/graduate-authentication-verification.txt` and browser screenshots under `tmp/graduate-authentication/screenshots/`. It does not call live providers or send email. The separate MySQL migration results for this implementation are recorded under `tmp/graduate-authentication/mysql-verification.txt`.

Test uploads are isolated under `tmp/graduate-authentication/test-uploads/`. A browser download and its checksum are saved under `tmp/graduate-authentication/download-artifacts/`.
