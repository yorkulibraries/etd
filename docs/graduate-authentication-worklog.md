# Graduate authentication worklog

## Original goal
Provide an alternative to Passport York for graduates returning to ETD for embargo requests and future modifications.

## Current goal
Commit and push graduate-authentication, wait for its GitHub CI to pass, then merge into staging and push. The user explicitly authorized both pushes on 2026-10-14. Server deployment, real provider testing and Apache activation remain separate.

## Branch publication, 2026-10-14
- Confirmed iota staging runs etdqa.service (Puma), loads /home/etdqa/.etdqa, and currently lacks the OAuth code.
- Committed the OAuth implementation as a5d2319. Left unrelated embargo planning documents untracked.
- The feature branch started at d3a69a2, older than origin/staging c8d1f05. Integrate current staging before CI so the tested branch retains staging fixes and submission snapshots.
- Integrated staging in c2f3c94, preserving current schema, invitations, submission snapshots and dependency fixes. Unified protected document downloads with existing embargo authorization.
- Local merged checks passed: 82 OAuth integration tests (1,568 assertions), 9 graduate/snapshot browser tests (206 assertions), and 41 document/session/snapshot checks (184 assertions). Both snapshot download checksums passed. Tests used port 3220 and an isolated database; existing manual demo was preserved.
- Next: push graduate-authentication, wait for successful CI for its exact commit, then merge and push staging. Google secrets are excluded from the commit.

## Google Cloud setup, 2026-10-13
- The user explicitly requested the first Google-provider setup step through Computer Use.
- Inspected the signed-in LDSI YorkU account. No ETD project existed; created the separate York ETD Staging project, ID york-etd-staging, and verified it was selected.
- Prepared app name York ETD Staging, the available account support/developer contact and External audience in testing mode. No other application's configuration was changed.
- Paused at the unchecked Google API Services User Data Policy agreement. The Computer Use confirmation policy requires action-time approval before accepting a binding agreement. Browser page is retained for continuation; proof is tmp/google-cloud-setup/consent-policy-review.jpg.
- OAuth client credentials and the staging callback are not created/registered yet. Continue after agreement approval, prepare the web client with the documented staging callback, and obtain the required action-time confirmation before creating persistent OAuth credentials.

## Passport York button, 2026-10-13
- The user requested matching shades after reviewing the outlined version. Added computed-color checks before changing Passport York to the same primary button style as Google.
- Matching-shade refinement complete: eighteen running-demo checks passed, including identical background/text colors on desktop and mobile. Inspected both updated screenshots. Latest results: tmp/graduate-signin-button-check/matching-shade.log. Demo remains running with existing data.
- The user requested a button beneath Continue with Google instead of the separated text link. Wrote geometry, destination, POST/CSRF and viewport checks before the view edit; the original text link failed the button check.
- Grouped the actions in the existing vertical grid, with Google primary and Passport York outlined. Kept the PPY link available when Google is disabled and retained the invitation return link.
- Completed: seven existing application browser tests passed with 125 assertions, covering sign-in, provider-unavailable and invitation flows. Fourteen running-demo checks passed for desktop/mobile button styling, equal widths, alignment, ordering, destination, Google POST/CSRF and PPY navigation. Inspected both rendered screenshots.
- Repeatable layout check: docker exec -w /app etd-graduate-auth bundle exec ruby tmp/graduate-signin-button-check/verify.rb. Results and screenshots are in tmp/graduate-signin-button-check/. The demo is running without a data reset or deployment.

## Local runtime recovery, 2026-10-13
- After connectivity was restored, the user reached the invalid-login page through /login. Added local-wrapper redirects from /login and /invalid_login to explicit sample sign-in choices on /demo. These redirects do not authenticate an account; selecting a sample actor still uses the existing PPY controller flow.
- Wrote browser failure scenarios and entry-point checks before the wrapper edit. The original /login failed the choices check. Final running-demo verification passed 20 checks: both entry redirects, explicit simulation, no automatic authentication, both sample actors, the public page's PPY link and desktop/mobile fit. Inspected the actual choice-page screenshots.
- Verified the production sign-in controller hash is unchanged and restarted without a data reset. An initial browser attempt ran before the cold server startup finished; it was not passing evidence. After HTTP readiness was confirmed, the final browser run passed. Evidence and repeatable script: tmp/graduate-demo-login-check/verified.log, result.json and verify.rb.
- The Docker daemon was stopped and the ETD container had exited, so localhost:3210 refused connections. Started Docker Desktop, the existing etd-graduate-auth container and its existing demo server without resetting data.
- The user noted the Multipass merge. Fetched ETD and YUDL upstream metadata and confirmed Multipass belongs to yorkulibraries/yudl-playbook main. ETD's default branch is master and still contains Docker development configuration. Multipass itself does not require Docker; the projects use separate runtimes.
- Preserved both working checkouts and their local edits. No checkout merge or pull was needed to restore ETD.
- Confirmed /demo and /graduate/login return HTTP 200. /login responds with its expected redirect to /invalid_login without real Passport York headers; use the sample sign-in links on /demo for local testing. Browser smoke evidence is tmp/graduate-manual-demo/restored-smoke-20261013.txt.

## FGS record header, 2026-10-13
- The user requested grouping the existing graduate account management action with Login as this student.
- Wrote placement, duplicate-link, destination and viewport checks before the view edit. The original action was outside the header paragraph.
- Moved the link into the student record header and removed the separate button below the divider. Preserved the existing manager/admin check and student-show page scope.
- Completed: seven application browser tests passed with 125 assertions. The final running-demo placement check passed ten checks for desktop/mobile link uniqueness, placement, destination, viewport fit and navigation. Inspected the rendered screenshots and kept each action label together when the header wraps on mobile.
- Repeatable placement check: docker exec -w /app etd-graduate-auth bundle exec ruby tmp/graduate-header-check/verify.rb. Results and screenshots are in tmp/graduate-header-check/; final.log records the latest layout checks. The separate button is removed and the local demo is running without a data reset or deployment.

## Student dropdown, 2026-10-13
- The user refined the request: remove the main-navbar link and rename the dropdown item Account connections. Updated browser scenarios and navigation helpers before the view edits; the original main-navbar link caused the new check to fail.
- Completed the refinement: removed the main-navbar item and kept Account connections in the student dropdown. Updated demo instructions and student browser navigation while preserving the separate FGS management link.
- Final verification: seven application browser tests passed with 125 assertions, plus eleven running-demo menu checks on desktop/mobile. Inspected both dropdown screenshots. The initial isolated test database name was rejected by the existing test safeguard; corrected the runner to use a dedicated test-named database. Corrected a browser helper that had applied the menu label to the separate FGS link. Final logs: tmp/graduate-menu-check/system-verified.log and dropdown-only.log. The demo is running without a data reset.
- The user requested the connections link in the user dropdown shown in their screenshot.
- Wrote local browser failure scenarios and a repeatable menu check before the view edit. The original dropdown did not contain the requested item.
- Added the link for the existing student role, pointing to /my/graduate-connections. Use the existing sample student/manager and preserve the demo database during verification.
- Completed: restarted the local demo without resetting data. All nine browser checks passed for desktop/mobile opening, the destination page, logout visibility, viewport fit and staff visibility. Inspected the actual desktop and mobile dropdown screenshots.
- Repeatable check: docker exec -w /app etd-graduate-auth bundle exec ruby tmp/graduate-menu-check/verify.rb. Results and screenshots are in tmp/graduate-menu-check/. The local demo is running; refresh its page to load the updated menu. No deployment or database change was needed.

## Google-only direction, 2026-10-08
- The user requested removal of Facebook after the two-provider demo was made available. This replaces the earlier provider selection; prior two-provider verification below is historical.
- Inspected the identity schema, model and connection callbacks. Connecting Google stores its stable UID, the student link and connection metadata. It does not save the Google email or change the existing student contact email. No email-storage change was requested.
- Delegated Google-only application/dependency/test/setup changes and the separate manual-demo update to Sol with distinct file ownership. Stop the demo during application browser tests, then restart it with the updated Google-only flow.
- Verify rejection of removed Facebook requests, invitations and sessions, including old records; preserve Google linking, sign-in, logout, PKCE/nonce checks and single-use invitations. Keep production code for unrelated workflows and the canonical schema unchanged.
- Completed removal of the Facebook strategy, dependency, configuration and current setup instructions. Google remains the only external sign-in provider. Historical Facebook records are retained but hidden and unusable, and their old sessions cannot authorize access.
- Removal checks were written before application edits and first demonstrated six expected failures. Final focused HTTP verification passed 82 tests with 1,568 assertions; application browser verification passed 8 tests with 132 assertions; full regression passed 310 tests with 2,408 assertions. Bundle, script syntax and whitespace checks passed. Commands, source hashes and logs are in tmp/google-only-auth/verification.md.
- Updated and restarted the local Google-only demo at http://127.0.0.1:3210/demo. Its running-server browser verification passed 30 checks, including linking, returning sign-in, logout, Google invitation enrollment/reuse and removed Facebook endpoints. Reset/restart smoke checks passed and fresh sample accounts are ready. Artifacts and manual steps are in tmp/graduate-manual-demo/.
- Parent reviewed the application delta and actual desktop/mobile output. Final independent requests returned 200 for the demo/login and 404 for Facebook initiation. Confirmed three sample users with no connections, invitations or graduate sessions, and no email column in the identity table. Tests also preserve both student email fields when the Google response contains a different Gmail address.
- The canonical MySQL schema and inherited thesis/permission diffs match their pre-removal snapshots. No migration, deployment, commit, push or real provider call was made. The earlier two-provider correction report is explicitly historical.
- Google-only removal and manual local testing are complete. Real Google consent and staging Passport York/Apache verification remain pending provider credentials and server configuration.

## Manual testing, 2026-10-08
- Checked the current branch and local HTTP endpoint. Both Docker containers are running, but no application server is listening successfully on port 3210.
- The application container has no graduate OAuth feature flag or Google/Facebook credentials configured. Real provider sign-in is not enabled.
- Delegated a local manual demo to Sol, using a separate synthetic database and simulated provider responses. The existing port is bound to 127.0.0.1 on the host.
- Completed: the local demo is running at http://127.0.0.1:3210/demo. The actual graduate sign-in page is /graduate/login. Demo code, data, provider simulation and sample PPY entry points are confined to ignored tmp/graduate-manual-demo/.
- Running-server Selenium verification passed 29 checks, including both providers' linking/return/logout flows, CSRF rejection, required confirmations, unlinked-account failure and one-use FGS invitation enrollment. Parent inspected desktop/mobile login, the demo instructions and mobile connections screenshots.
- Verified stop/reset/restart and browser smoke checks. Parent independently confirmed both HTTP endpoints return 200, the three sample accounts are present, and connections, invitations and graduate sessions are empty for manual testing. Stop waits for the process to exit before reset deletes the isolated database.
- Previous authentication source hashes and the canonical MySQL schema are unchanged. No production application code, existing database, staging deployment, commit or push was changed.
- Manual steps and start/stop/reset/repeat-verification commands: tmp/graduate-manual-demo/README.md. Repeatable results: verification.json, verification.txt and restart-smoke.txt in that directory.
- Remaining for real provider testing: configure university-managed Google/Meta credentials and verify the staging Passport York/Apache boundary. The local demo simulates all external sign-ins and does not validate live provider consent or exchange.

## OAuth correction, 2026-10-06
- The local branch review confirmed missing graduate-session expiry and logout revocation. Existing thesis permission findings are outside the authorized correction scope.
- Strengthen provider transaction checks after inspecting the installed strategies and provider documentation. Do not assume Meta supports an undocumented PKCE option.
- Write request-flow failure checks before changing application code. Use isolated local databases and preserve the canonical MySQL schema.
- Next: finish the independent boundary review, implement graduate-only session controls and supported provider checks, then verify sign-in, linking, logout, PPY compatibility, and migrations. No deployment, commit, or push is authorized.
- Completed the independent boundary review and delegated the graduate-session implementation to Sol. Added digest-only, revocable sessions with a fixed 12-hour lifetime. Old graduate cookies require a new provider sign-in; PPY and staff support retain their existing session behavior.
- Added Google S256 PKCE, one-use nonce checks, required ID-token claim checks and subject consistency. Restricted both strategies to the registered server-side code flow and fixed Facebook authorization options.
- Added middleware validation of graduate session metadata before determining login or linking intent. Coordinated returning sign-in with the student lock used by connection revocation.
- New failure and request checks preceded the corresponding application changes. Provider and middleware checks first demonstrated the missing controls; final focused checks passed. A middleware expiry probe was moved clearly past expiry to avoid wall-clock microseconds; separate session checks verify the exact 12-hour boundary.
- Parent full Rails verification: 302 tests, 2,368 assertions, no failures/errors/skips. Isolated MySQL migration up/down/up and 17 session HTTP tests with 497 assertions passed. Artifacts are under tmp/oauth-correction/.
- Remaining: finish focused browser verification and independent candidate review, then record the final status. Deployment and live provider/Apache verification are still separate.
- Independent candidate review identified three OAuth lifecycle cases. Added request checks before corrections, then revoked all graduate sessions when a Student is blocked, made invitation consumption and session issuance one transaction, and retained the public logout destination when a graduate session has expired. The Student callback changes only graduate-session revocation.
- Final MySQL verification passed 20 session/lifecycle tests with 540 assertions. The repeatable runner passed 77 request tests with 1,571 assertions and 7 browser tests with 115 assertions. Syntax checks and diff whitespace checks passed. The inherited thesis controller and ability changes match their pre-correction snapshot.
- A broader plain Rails run hit an existing async export-job/SQLite cleanup lock. It was interrupted and is not passing evidence. Retried with the standard Rails test job queue and fake OAuth configuration loaded before boot; full verification passed 305 tests with 2,411 assertions. Temporary runner boot errors were corrected without changing application export code or the common test harness.
- OAuth correction is local and uncommitted. Apply the new session migration before restarting a deployed application; existing graduate OAuth cookies then require fresh sign-in. Live Google/Meta and Apache verification still remain before activation. Inherited thesis/embargo findings were intentionally left outside this correction.
- Final full regression with the prior lock seed 27551, fake OAuth settings loaded before boot, and the test job queue: 305 tests, 2,411 assertions, no failures/errors/skips. Saved exact rerun commands and source hashes under tmp/oauth-correction/. Plain results: docs/graduate-oauth-correction-verification.md. Local OAuth patch and verification are complete.

## Findings
- The checkout started on master at d3a69a2. Work is local and uncommitted on graduate-authentication. Existing untracked embargo planning documents are preserved.
- Passport York authentication uses trusted request headers and maps them to an existing User or Student.
- The application stores the local user ID in its session. External sign-in must resolve to that same student, without creating duplicate student records or granting staff privileges.
- Student records already contain an external contact email, but an email match alone is insufficient proof for linking an external identity.
- Existing permissions restrict normal thesis editing to open or returned records and permanent embargo changes to managers/admins. Alternative authentication does not implement the separate embargo-request workflow.
- Production reverse-proxy authentication configuration is absent from this checkout. Graduates must be able to reach the app and OAuth callback without a compulsory Passport York challenge.

## Completed
- Inspected sessions, Warden strategy, student/user models, routes, permissions, and local runtime.
- Checked Google's current OpenID Connect documentation. Use the stable provider subject as identity, not email.
- Confirmed there are no running project containers; an existing etd-web image is available.
- User selected both Google and Facebook.
- Created local branch graduate-authentication.
- Delegated application implementation and end-to-end verification to Sol with extra high reasoning and no inherited turns. Parent owns deployment documentation, integration review, and final verification.
- User supplied staging origin https://etdqa.library.yorku.ca and believes Apache enforces Passport York. Treat Apache as unconfirmed until its actual configuration is inspected.
- Read-only HEAD requests to the staging root and /login returned 403 from Apache/2.4.58 (Ubuntu), confirming Apache is present. This environment cannot inspect the staging application or infer its exact Passport York configuration from that response.
- Added staging/provider setup documentation, including account ownership and the Apache routing boundary.
- Worker persisted failure scenarios, request-flow tests, browser tests, and initial screens. Main integration review raised PPY provenance, session revocation, and invitation URL logging requirements before completion.
- Parent independently reran existing Passport York/session and student-view tests: 17 runs, 69 assertions, no failures or errors.
- Parent inspected desktop and mobile login screenshots; layout and visible controls passed review.
- New browser flow suite reached 6 runs, 108 assertions, no failures or errors after fixes.

## Direction change
The Apache handoff exposed a necessary integration concern: existing downloads link directly to files under public/uploads. Relaxing Passport York at the edge must not make these files public. Extend this change with authorized document downloads and denial of raw upload URLs, with failure scenarios written before implementation. The embargo workflow and editing permissions remain outside scope.

Final broader verification found two more integration requirements: legacy browser login helpers relied on cached Warden users rather than Passport York proof, and old staff report/account-list pages lacked student-role guards. Update only the test login boundary and these staff page guards; preserve student /my and thesis editing behavior.

## Verification history
- Focused request flows: 35 runs, 414 assertions, no failures/errors.
- Focused browser flows: 7 runs, 115 assertions, no failures/errors; downloaded PDF matches the fixture checksum.
- MySQL migration up/down/up passed with binary provider UID collation.
- Parent full Rails suite before the final staff-page guards: 263 runs, 1254 assertions, no failures/errors.
- T3 preview navigation and DOM inspection succeeded; snapshot capture failed twice. Saved Selenium desktop/mobile screenshots were inspected instead.
- Full legacy browser run exposed the cached-user helper problem and was stopped for correction. Recheck it after updating the test-only header boundary.
- Staff-page boundary request checks passed. Parent full Rails suite after these guards: 267 runs, 1412 assertions, no failures/errors.
- Combined browser execution exposed a shared-server port mismatch; standardized the legacy harness on the same local port as graduate flow tests.
- Broader browser coverage found a real support-flow regression: active staff impersonating a blocked student lost the return session. Preserve verified active-staff impersonation, revoke it when the staff actor is blocked/deleted, and keep blocked students' own sign-in and account linking denied. Reverify before finishing.

## Next step
Activate and verify on staging after university-managed provider credentials and the actual Apache/Passport York routing configuration are available. No changes have been deployed, committed, pushed, or emailed. See graduate-authentication-setup.md for the exact callbacks, environment variables, and server requirements.

## Final integration review
- Confirmed and fixed the nested thesis contact-update route accepting foreign thesis IDs and bypassing closed-thesis edit restrictions. Failure requests were written before the correction. The route now scopes the thesis to the authorized student and checks the concrete thesis permission before updating contact information.
- Preserved active staff support impersonation, including legacy signed sessions, while rejecting social account linking during impersonation and revoking access when the staff actor becomes invalid.
- Isolated test uploads from local application uploads and prevented SQLite verification from rewriting the canonical MySQL schema.
- Parent full Rails verification after all corrections: 276 runs, 1694 assertions, no failures, errors, or skips. Report: tmp/graduate-authentication/parent-regression.txt.
- Parent full browser verification after all corrections: 53 runs, 300 assertions, no failures, errors, or skips. Report: tmp/graduate-authentication/parent-system-regression.txt.
- Visually reviewed the latest graduate login and invitation enrollment mobile screenshots, plus earlier desktop and FGS management screens. Authorized browser download checksum matches the fixture. Artifacts are under tmp/graduate-authentication/screenshots and download-artifacts.
- The repeatable verification runner passed after all integration changes: 48 request-flow tests with 854 assertions, and 7 browser tests with 115 assertions. Its complete command/results artifact is tmp/graduate-authentication-verification.txt.

## Google Cloud staging setup, 2026-10-13
- Current goal: create the Google OAuth staging client through the user's open browser, without putting credentials in Git or chat.
- The user approved Google API Services User Data Policy acceptance. Saved the consent configuration in project York ETD Staging (york-etd-staging); Google visibly confirmed "OAuth configuration created!".
- Prepared a Web application client named York ETD Staging Web, with redirect URI https://etdqa.library.yorku.ca/graduate/auth/google_oauth2/callback and no JavaScript origins.
- Browser page controls became unavailable; continued through Computer Use native Helium window controls and verified the prepared form. Screenshot: tmp/google-cloud-setup/client-review.png.
- Next step: obtain action-time confirmation required by the Computer Use policy before clicking Create to generate persistent OAuth credentials. The client has not been created yet. Server deployment and real sign-in verification remain outstanding.
- The user approved creation. Clicked Create and verified Google's "OAuth client created" confirmation, with enabled credential status. The client uses the staging callback prepared above.
- Google warns that the client secret cannot be viewed or downloaded after closing the creation dialog. Left this dialog open for the user to securely save the credentials; did not download, copy, or record the secret. Proof screenshot excludes the credential area: tmp/google-cloud-setup/client-created.jpg.
- Next step: securely capture the new credentials, configure the staging server, deploy and verify real Google linking/sign-in. Production credentials have not been created.
