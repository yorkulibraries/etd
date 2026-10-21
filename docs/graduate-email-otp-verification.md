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
Task 8 adds operations/cleanup/control and actual two-worker restart checks.
Workers consume both `graduate_email` and `graduate_email_notice` exclusively.

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

## Task 8 local operations gate

See the [operations/FGS runbook](graduate-email-otp-setup.md). Before full gates,
write failure scenarios and operations tests, capture their expected RED failures,
then implement. The runner now discovers both operations integration files,
including real guarded command subprocesses and two installed foreground worker
processes. Fake SMTP stays in private RAM; no real relay/provider is contacted.

Use a NEW run name, for example `GRADUATE_EMAIL_VERIFICATION_RUN=task8-final`,
for each adapter's full runner. Preserve historical Task7 default/task7-r1 packages.
The runner alone owns its unsealed capture directory. Broad suites run with
GRADUATE_EMAIL_ARTIFACT_DIR unset: clean-state assertions stay active, no PNG is
written. After source freeze, run sequentially for each adapter: operations files,
full OTP runner, justified broader application/browser regressions and autoload check,
then scan sealed artifacts and compare all frozen host/container hashes. Cookie,
retention and session interactions justify the broad regression here. Inspect
actual clean desktop/mobile outputs from the new runner; no token/code/unsafe DOM
capture. Native preview mobile/images previously failed; repository Chrome PNGs
are the accepted local fallback. Real devices remain an external gate.

```bash
bash script/verify_graduate_email_storage sqlite exec ruby test/support/graduate_email_task5_test_reporter.rb test/integration/graduate_email_operations_test.rb test/integration/graduate_email_worker_operations_test.rb -v --seed=27183
GRADUATE_EMAIL_VERIFICATION_RUN=task8-final bash script/verify_graduate_email sqlite
bash script/verify_graduate_email_storage sqlite exec bundle exec rails zeitwerk:check
systemd-analyze verify config/deploy/graduate-email-worker.service config/deploy/graduate-email-cleanup.service config/deploy/graduate-email-cleanup.timer
```

Repeat through the same guard with mysql, sourcing the private container file with
tracing off as above. Never pass a URL on the command line. Both URL variables must
remain identical in every Rails/worker/browser child. No framework/schema/gem change
is required. Parser absence is **unverified until QA**, never permission to install
privileged services. An available container parser verifies syntax only, not host
systemd version, real service install/user/env/paths, restart policy execution or TLS.
The two-process local gate kills/restarts queued work on both private queues, reclaims
stale backend locks after synthetic clock advancement, proves claimed OTP/notice
state never retries, preserves a default-queue sentinel and joins all children.
It does not install or run host services.

## Important-finding fixes I1/I2

The runner discovers these regressions in existing files; no new runner list.

- **I1 (approver turnover).** Returning login keeps working when the historical
  approver of a verified connection is demoted or blocked. This holds before the
  request, between request and worker, and between delivery and redemption, through
  real HTTP/CSRF, a persisted job, RAM transport and the browser flow. Existing
  email and Google sessions stay valid. A pending initial or recovery approval whose
  approver is demoted or blocked is still denied at intent, request, send
  authorization and redemption.
- **I2 (worker configuration).** Fresh installed `rake jobs:work` processes with
  `GRADUATE_EMAIL_WORKER=1` and missing or invalid configuration exit non-zero with
  a fixed line before any reservation. Queued jobs and rows stay byte-identical and
  no sentinel value is printed. An ordinary boot and a default worker are unchanged.
  A configured dedicated worker still delivers a notice while the feature is
  disabled. Configuration lost after start turns queued real challenges and notices
  into visible `failed` rows with fixed diagnostics and no code, mail or retry.
  Status reports stale queued counts.

Use a new run name such as `GRADUATE_EMAIL_VERIFICATION_RUN=opus-important-fixes-r1`;
historical packages stay untouched.

## Minor fix M4 (first code request)

Opening an invitation, refreshing, going Back or a link scanner fetch creates intent
only and queues no mail. The page says no code has been sent yet and offers one
primary Send code POST. After any send POST, including address entry, the generic
message, code field and Resend code appear. Invalid, expired, revoked, used and
malformed invitations render the same pages and send nothing. The page state comes
only from this browser's request history, never from invitation, target or
challenge state. A verify page with no transaction offers address entry instead.
Use a new run name such as `GRADUATE_EMAIL_VERIFICATION_RUN=opus-first-code-ux-r1`.

## Owner-approved QA checklist, before any enable

This checklist authorizes no QA data, requests, mail or provider changes. Supply
actual values and approvals in a protected QA record; do not publish identifiers.

| QA value | Required owner-provided value |
| --- | --- |
| Public HTTPS origin and vhost/config path | PENDING |
| Edge/proxy chain, trusted peers and PPY authenticated boundary | PENDING |
| Exact release root, Ruby/bundle path, worker and web units | PENDING |
| Upload storage root, every alias/CDN/direct route and snapshot storage | PENDING |
| Protected environment/secret-store references | PENDING |
| Primary DB host/version, app pools and connection budget | PENDING |
| Controlled student/mailboxes, FGS procedure reference/version/contact owner | PENDING |
| Mail relay, transport/sender/SPF/DKIM/DMARC owner and testing capacity | PENDING |
| Monitoring, cleanup/QA record retention and sign-off owners | PENDING |

1. Freeze the reviewed release/commit and rollback. Keep email disabled. Through
   the existing deployment process apply reviewed migrations, preserving unrelated
   delayed jobs. Check actual MySQL version/enforced CHECKs, all NOT NULL/defaults,
   two independent active mapping unique indexes, binary address collation and
   every audit `ON DELETE SET NULL` FK. Verify primary routing, UTC/time sync and
   actual lock deadlines. Resolve database pool capacity for web plus two workers,
   cleanup and existing consumers. Record categories/counts, not student data.
2. **Before the first invitation request**, redact token query values in proxy
   request lines, access/error logs, Rails and APM. A filter on parsed query alone
   does not redact `$request` or raw request-target. Confirm with synthetic sentinel
   traffic in the approved QA process; no raw token values enter evidence. Disable
   request-body/mail/SMTP/APM payload/referrer capture, analytics/session replay on
   these pages and automatic failure HTML/screenshots. Use no-referrer/no-store.
3. Review the actual vhost: public HTTPS `/graduate/login`, `/graduate/email*`,
   existing OAuth POST/callback routes and assets must work. Staff routes retain
   app authorization. Apply the planned 2 KiB body/global/IP caps at the edge without
   preventing OAuth/assets. Strip PPY identity headers on every public/untrusted
   hop; only authenticated PPY boundary may add them. Test forged PPY identity,
   X-Forwarded-For/Forwarded/real-IP and scheme headers through each real route.
   An untrusted immediate peer must not choose throttle identity. Record network
   checks showing the configured trusted peers and canonical send/redeem IP agree.
4. Deny **all** direct/alias `/uploads` paths, alternate hosts/CDN/static locations,
   URL encodings and symlink aliases. Verify owner-authorized current downloads,
   owned snapshots according to existing policy, foreign-owner denial, and public
   direct denial using actual controlled document bytes. Do not infer this from
   Rails routes alone. Preserve release/storage ownership and historical snapshots.
5. Verify forwarded HTTPS scheme, actual `_etd_session` Secure/HttpOnly/SameSite=Lax
   flags, same-site callback behavior, browser CSRF/missing/wrong-origin rejection,
   no-store/referrer headers and logout rotation. Never weaken Secure or trust
   arbitrary forwarding to make HTTP work. Verify Google/PPY remain responsive.
6. Resolve and parse actual service templates. In the authorized QA environment,
   prove two workers consume only both dedicated queues after restart; default jobs
   remain untouched. Prove queued survival and claimed/ambiguous no retry with
   synthetic mail first. Verify cleanup hourly timer/reboot persistence, last-success
   monitoring, heartbeat/oldest/failure alerts and safe journal contents. Measure
   cleanup transaction sizes/duration and sustained ingress/retention backlog.
7. Only after the above and FGS/mail/proxy/operations owners approve, enable QA using
   the protected authorized operator. Record generation and categories/counts only.

## Controlled real-mail and capacity checks, future QA only

Mail owner must approve controlled recipients and relay capacity first. Inspect TLS
certificate verification, approved authentication/transport, exact sender and sender
SPF/DKIM/DMARC alignment/policy with that owner. Check exactly one approved recipient,
leading-zero code by manual entry without capture, delivery timestamp/5 min expiry,
delay, error, explicit resend and no automatic retry. Stalled SMTP may accept stale
mail later; the code must fail redemption after disable/block/revoke/resend. Do not
assert delivery or TLS from the private RAM transport or local service parser.

For timing, make 200 requests **per class** known/unknown/throttled using approved
synthetic fixtures and randomized/interleaved order. Space requests and allocate
fixtures to preserve each classification within the real limits, rather than turning
all known requests into throttled ones. Save only class, HTTP status and duration.
Compare distributions: flag a median difference>20 ms or p95 difference>50 ms for
investigation. Do not add an artificial delay or claim async design proves enumeration
safety. Publish numeric results and classification/capacity limits, not addresses.

Measure 20 concurrent synthetic operations under both normal and 10 s-stalled relay.
Record queue depth, p95, lock wait, denial counts and DB pool utilization. Require no
send/verification/retained-job limits violated, generic response within 5 s, disable
and real model/controller block completion within 5 s **while SMTP is stalled**, and
Google issuance/PPY responsiveness. Record actual normal/stalled latency and lock-wait
numbers. Confirm no network I/O inside a DB transaction. Use integration barriers for
races rather than exhausting real mailboxes; investigate measured bottlenecks before
reviewed tuning and keep specification minima. No local performance result is implied.

## QA completion and owner sign-off

Use two actual HTTPS browsers plus desktop/mobile layouts for initial enrollment,
returning sign-in, wrong/expired/reused/cross-browser/cross-purpose codes, leading
zeroes, same-browser resend, other-browser code survival, send throttles with valid
verification, logout, block/unblock, replacement/recovery/revocation, paused work and
a browser dormant across disable/re-enable. Verify old approvals/codes/cookies fail
and fresh sign-in needs a new generation. Inspect FGS confirmation/token-once/cancel/
reissue/notice states and staff-denied/student boundaries. Verify configured Google
real callback and PPY through their actual boundaries. Local fake callbacks do not
replace this. Include real-device/assistive checks where required by the owner.

Evidence uses only safe categories/counts, approved safe record references in the
protected QA system and clean allowlisted screenshots with no token/code/address
identifiers. Never archive raw logs, mail, unsafe DOM or entered code. Obtain FGS,
mail, proxy and operations sign-offs; attach resolved service/migration/index/time/
capacity/latency/cleanup/restart evidence and remaining limits. Clean controlled
records, own jobs and RAM/mail captures per QA policy while preserving audit policy.
Then disable and advance generation, stop/reconcile QA workers as directed, and
prove stale access remains denied. Leave email disabled unless an explicit authorized
QA continuation says otherwise. Production deployment **and** activation need separate
owner approvals after QA. Follow the rollback compatibility instructions in the
operations runbook, never destructive down migrations or restoration of old generation.

## Task 8 fix regression checks

On the Docker host, select the already installed reviewed image (no pull):

```bash
python3 test/support/graduate_email_container_probe.py --image IMAGE_ID --workers
```

This resolves both worker templates using the unpopulated example file and a
numeric nonroot test identity, checks actual private mount writes and identity
rejections, then uses a disposable network-disabled container with the resolved
user/tmpfs/read-only/capability/logging/stop settings. The local image predates installed gems, so this harness copies only the existing
runtime dependency code, including locked Git gem checkouts, into a disposable
read-only volume. It excludes bundle config/cache, Git metadata and server
environment files, verifies dependency hashes before/after copying, and removes
the volume afterward. No dependency download or image build occurs.
The checkout is read-only; SQLite is created only on its private tmpfs at the existing guard's allowlisted
path. Actual foreground jobs:work processes exercise both dedicated queues with
RAM transport, queued restart, claimed no-retry and an unrelated queue sentinel.
The test command replaces production boot solely to prepare the disposable DB
and install the existing test transport. It does not install a host service or
validate production secrets, an owner-specific image, relay or supervision.

The worker operations integration file also runs
`test/support/graduate_email_worker_lifecycle_probe.rb` in dedicated and ordinary
roles. This no-DB check uses the installed Worker's real start/work_off/perform
lifecycle, synthetic execution and a private monotonic clock. It checks busy and
idle heartbeats, rate bounds, static output and unchanged ordinary defaults.
Run both operations integration files through the storage guard sequentially
on SQLite and MySQL after a pre-gate host/container source freeze. Use the
existing sanitized reporter. These scoped worker/template fixes do not require
repeating broad exports or rewriting any sealed Task 7/8 runner package.
