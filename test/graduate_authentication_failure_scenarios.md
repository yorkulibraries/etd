# Graduate authentication failure scenarios and E2E specification
Written before application implementation. Parent owns documentation and worklog.

Goal: opt-in Google access to the same active Student and theses, using an explicitly linked stable provider UID. Preserve Passport York and all existing permissions. No external email, provider calls, deployment, commits, or pushes.

Final integration failure scenarios, recorded before corrective changes:
- Legacy browser tests use Warden's cached-user shortcut. Visiting /login must still reject that shortcut as Passport York proof. The test harness must inject a one-use trusted-header boundary on /login and exercise real session creation instead.
- Students must not reach staff reports, account lists, or other students' list/audit/search pages, through either Passport York or graduate sign-in. Own /my pages and existing staff access must continue to work.
- File fixtures from isolated test databases must not share upload directories with local development data. Keep test uploads and their cleanup under the task's temporary directory.

Failure scenarios:
- Disabled or incomplete provider configuration, invalid callback base, unknown provider, GET initiation, missing or invalid Rails CSRF token, missing/mismatched OAuth state, provider cancellation, missing middleware auth/strategy, missing UID, unverified Google email claim.
- Same email without a linked UID, supplied student ID/mode, expired/missing/mismatched enrollment intent, callback without initiation, conflict with another student, replacement of existing provider identity.
- Blocked or deleted student, blocked user after login, staff or impersonated student linking, social-only session attempting another provider, regular staff invitation/revocation, missing identity verification confirmation.
- Invalid/expired/reused/superseded invitation, conflict must roll back consumption, GET invitation must neither consume nor authenticate, concurrent consumption must be single-use.
- Logout leaves Warden/local session state, social login gains staff permissions, access to another student's thesis, tokens/code/secrets in database, audit trail, or logs.
- PPY staff receives CYIN but has no Student record: trusted username must still sign in. CYIN and username resolving to two different known accounts must reject the request rather than silently switch roles.
- Browser forms on a no-referrer page can send Origin:null, which Rails must continue rejecting. Token entry keeps no-referrer and redirects cleanly; normal form pages use same-origin referrers so legitimate browser POSTs retain their Origin.

Request-flow specification, through Rails and OmniAuth middleware:
1. Actual PPY headers create a reset PPY session, route as before, preserve student username update and staff route. Blocked/absent headers cannot establish PPY provenance.
2. Actual PPY student POSTs a CSRF-protected provider form, mock trusted provider callback creates one identity, same student and thesis on anonymous return. No matching by email and no account creation.
3. Active admin/manager with checked out-of-band confirmation creates 48-hour digest-only invitation. Public GET establishes only short-lived enrollment intent. Callback atomically creates identity and consumes invitation. Expiry, reuse, supersession, wrong provider, conflict, and missing confirmation fail closed.
4. Explicit confirmed unlink only PPY self or admin/manager; staff, impersonation, and external-only sessions denied. Existing student authorization and other student's thesis remain denied.
5. Real middleware request phase rejects GET/CSRF failures. Real strategy callback rejects missing/wrong state before mocked provider network boundary. No live provider calls.
6. Unlinked account, missing UID, Google email verification false, cancelled OAuth, unknown provider, invalid/missing intent all show an actionable generic page.
7. Full logout clears local/Warden state; PPY York logout and external public-login destinations remain distinct. Subsequent blocking clears sessions.

Browser/system specification:
Independent system test class, no implicit staff login. Mock only provider/PPY boundary. Verify public login on desktop/mobile, PPY connection settings, connection action and confirmed unlink, admin invitation confirmation and copyable URL, anonymous enrollment, callback, returning login, cancellation. Save screenshots in tmp/graduate-authentication/screenshots. Repeatable runner saves tmp/graduate-authentication-verification.txt with commands/results. Live Google app configuration and upstream Passport York header trust remain outside mocked verification.

## Authorized download integration (added before download code)
Raw CarrierWave URLs currently live under public/uploads. Public graduate routes make protecting the file-serving boundary necessary. Preserve all existing edit permissions and embargo workflows.

Failure scenarios: anonymous download, another student's thesis/document ID, mismatched parent IDs, blocked or revoked social session, closed thesis wrongly requiring edit permission, deleted/missing/unreadable file, traversal or symlink escaping the document's upload directory, raw /uploads through Rails static server (including encoded/dot-segment path variants), raw uploads served directly by Apache.
Downstream application errors retain their existing handling; only path decoding and normalization errors may be converted to a controlled denial by the upload guard.

## Staff support impersonation correction (specified before code)
Failure scenarios: an active admin, manager, or staff member loses the return session when opening a blocked GEM Student through the existing Login as action; a legacy signed staff session without auth_source is incorrectly rejected; a blocked, deleted, or no-longer-staff return actor retains access on the next request; a non-Student target is accepted as impersonation; blocked real Student PPY/OAuth sign-in becomes allowed; an external Student can create a return actor flag; impersonation can connect a provider or consume a linking intent.

Request-flow E2E specification:
- For each active admin/manager/staff role, sign in through actual PPY headers, impersonate a blocked Student, read the Student's own /my details, reject provider connection, and use logout_as to restore the same staff account.
- Repeat that support flow with a genuine Rails-encrypted legacy session cookie lacking auth_source. An active staff return actor attests this existing signed-session impersonation.
- Block or delete the return actor after impersonation, for blocked and active Student targets, and verify the next /my request clears the full authentication and return session.
- Reject signed-session fixtures with a Student return actor, changed actor role, non-Student target, or graduate_oauth provenance.
- Confirm blocked real Student PPY and linked OAuth remain denied and an external Student cannot use the existing login_as action to establish impersonation.

## Thesis contact ownership correction (specified before code)
Failure scenarios: a student submits another student's parent and thesis IDs; a student's own parent ID is paired with a foreign thesis ID; a closed own thesis uses the contact update endpoint to bypass the existing edit restriction. Verify foreign records remain unchanged and own open updates still work through Passport York and linked graduate sign-in.

Request/system E2E specification:
- Upload a real fixture to an existing Student's thesis, sign in with linked provider, download authorized endpoint and compare bytes to fixture. Content-Disposition attachment, no-store and nosniff.
- Own closed thesis remains readable through download; file edit permission remains denied. Authorized staff can download closed thesis.
- Anonymous/other student/incorrect parent IDs, deleted/missing/out-of-directory files cannot return file bytes.
- Rendered document download link uses authorized route, contains no raw /uploads URL. Browser click downloads repeatable fixture artifact and confirms content digest.
- Enable Rails static files and issue actual HTTP requests for real uploaded file under /uploads and encoded/canonicalization variants; each must be404. Middleware precedes Rails static serving. Apache must deny raw uploads too because it can serve files before Rails; staging enforcement remains a live deployment check owned by parent documentation.
