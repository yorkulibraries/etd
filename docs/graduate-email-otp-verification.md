# Graduate email sign-in verification

Run from the checkout using Ruby 3.1.4, Rails 7.0.8.1 and the installed pinned
bundle. Local Chrome follows the existing headless Selenium workflow. The runner
derives the checkout root and calls the existing storage guard for every Rails,
worker and browser child. Never run the default compose web startup for this gate.

```bash
bash script/verify_graduate_email sqlite
bash script/verify_graduate_email mysql
```

For the existing local container:

```bash
docker exec etd-graduate-auth bash -lc 'set +x; cd /app; bash script/verify_graduate_email sqlite'
docker exec etd-graduate-auth bash -lc 'set +x; source /tmp/graduate-email-mysql-env; cd /app; bash script/verify_graduate_email mysql'
```

The private MySQL environment file lives inside the container. It must provide
`GRADUATE_EMAIL_TEST_DATABASE_URL` for the dedicated `etd_graduate_email_test`
database and `GRADUATE_EMAIL_TEST_DATABASE_CONFIRMED=dedicated_disposable_test`.
Never print it, enable tracing or pass its values as command arguments. SQLite
uses only root-derived `tmp/graduate-email-storage_test.sqlite3`. Both inherited
URL variables are replaced identically by the storage driver. SCHEMA is under tmp.
These databases are destroyed by the migration gate. Run adapters sequentially
because uploads are shared. Leave existing listener 3210 untouched.

`ETD_SYSTEM_TEST_SEED` accepts digits only, default 27183. `ETD_SYSTEM_TEST_PORT`
defaults to 3425, which must be free. All browser assertions use real CSRF and
awaited destination/content selectors. No blanket retries or sleeps are added.

Each run performs fresh and seeded baseline/up/down/up storage checks, then all
implemented OTP integration tests and the exact ten existing authentication
integration files from `script/verify_graduate_authentication`. Browser checks
include both OTP files and the existing Google and download files. That older
hardcoded SQLite script is not executed. The frozen original Google insert,
persistent Google database default and unrelated durable-job sentinel remain
part of the storage probes. Constraint, concurrent admission/consumption/recovery,
notice capacity and five delivery crash barriers run against real disposable DBs.
Operations/cleanup/control commands and worker supervision belong to Task 8.
Workers must eventually consume both `graduate_email` and `graduate_email_notice`.

Before gates the runner freezes source SHA256 values and records branch, HEAD,
working diff digest and numeric seed. It checks these again afterward. Newly
created implementation files are included in source hashes. Result JSON contains
exact safe command arrays, exit statuses and the source check. Text reports retain
source-known test identities, fixed exception categories, counts and static probe
results only. Subprocess diagnostics stay in RAM. Versions include Ruby, Rails,
Delayed Job, its backend, database and Chromium. The manifest hashes every file in
the adapter's `tmp/graduate-email/verification/` directory. A later commit can have
a different HEAD; pre-commit evidence describes the recorded HEAD plus diff/source
hashes, never retroactively substitutes a new commit identity.

Automatic screenshot/HTML capture stays suppressed for graduate tests, including
failure pages and generated Google invitation pages. Only the explicit
`clean_browser_artifact` API may capture these named clean states at 1440x1000 and
390x844: login, generic-send, code-error, expired-enrollment, revoked-enrollment,
student-connection, staff-confirmation, staff-recovery and notice-states. Each
requires its documented route and heading, no query/fragment, no entered code,
no invitation/token DOM or token-bearing links/inputs and no horizontal overflow.
CSRF hidden fields are retained for functional tests and never exported as DOM.
Synthetic addresses may appear in reviewed connection/confirmation screenshots.
No code or invitation is captured. Long addresses, native required checkboxes,
keyboard focus, input labels/error association and all four notice states are
checked. These checks are not a full assistive-technology certification.

The scanner rejects unknown files, symlinks, non-PNG screenshots, URL/mail/bearer
content in text and known sentinel bytes without printing matches. CI uploads
only this directory's scanned report/JSON/PNG allowlist after manifest integrity
verification. No raw log, DOM, HAR, trace, database, mail, cookie, downloaded
student document or worker dump is uploaded. To repeat the publication check:

```bash
bash script/verify_graduate_email sqlite scan
bash script/verify_graduate_email mysql scan
```

Local transports capture synthetic mail in RAM, provider responses and trusted
PPY headers are mocked. Process barriers exercise persisted jobs and separate
connections; they establish the exercised orderings, not every possible schedule.
RAM mail is cleared and fake workers/transports stopped and joined before database
cleanup. No live SMTP, Google, external email, QA/prod, deployment or feature
activation is verified or authorized. Actual FGS procedures, relay/TLS/sender
policy, HTTPS/cookies/proxy trust and token redaction require later owner-approved
QA. Native preview appearance review is additional to repository Chrome tests.
Historical Task 6 full-suite reports have no pre-run source manifest; new Task 7
proof does not repair that historical limitation. Earlier unexplained Task 1
parallel MySQL and Task 2 SQLite failures remain unexplained.

Clean assertions also run in general browser suites. PNG writes require the
runner-owned `GRADUATE_EMAIL_ARTIFACT_DIR`; without it the helper validates the
same DOM, geometry and safety rules and returns without invoking image capture.
A destination containing `manifest.json` rejects further captures. General-suite
failures therefore cannot partially replace a sealed runner package. CI retains
the runner, broad application, broad browser, scan and conditional upload order.

For an isolated local rerun, set `GRADUATE_EMAIL_VERIFICATION_RUN=task7-r1` for
both runner and scan commands. Names accept 1 to 64 letters, digits, underscores
or hyphens, starting with a letter or digit. This selects
`tmp/graduate-email/verification/task7-r1/ADAPTER` for both writer and scanner;
leave the capture-directory variable unset for subsequent general suites.
Each full runner intentionally recreates only its selected package. Use a fresh
name to preserve historical evidence. CI uses the unchanged default paths.
