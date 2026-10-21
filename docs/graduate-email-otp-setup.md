# Graduate email sign-in operations

This is a local implementation and an installation template, not a deployment or
activation approval. Email starts disabled in the primary database. Google and
Passport York remain independent. Use this with the [verification guide](graduate-email-otp-verification.md)
and [approved design](superpowers/specs/2026-10-15-graduate-email-otp-design.md).

## Required owners and protected configuration

Fill the following before real records or controlled-mailbox QA. Blank means
pending, not approved. Do not substitute developer/test fixtures for approval.

| Prerequisite | Approved value or evidence |
| --- | --- |
| FGS named procedure owner | **PENDING: not supplied** |
| Identity verification procedure reference and version | **PENDING: not supplied** |
| Verified contact channel and mailbox control check | **PENDING: not supplied** |
| Lost-mailbox/reassigned-mailbox procedure and escalation owner | **PENDING: not supplied** |
| University retention schedule/authority for approvals/connections/audits | **PENDING: not supplied** |
| Mail owner, approved sender, authenticated TLS relay and sender policy | **PENDING: not supplied** |
| Proxy/vhost owner, actual QA and production hostnames | **PENDING: not supplied** |
| Release root, Ruby/bundle executable PATH, unprivileged app user/group | **PENDING: not supplied** |
| Protected environment file and secret-store references | **PENDING: not supplied** |
| Controlled student and approved mailbox owners | **PENDING: not supplied** |
| Operations monitoring/escalation and QA sign-off owners | **PENDING: not supplied** |

Use `config/deploy/graduate-email.env.example` as a list of required settings.
Populated environment files belong outside source/releases: root-owned directory
0750 and file 0640, app group read only, no broader readers. Protect secret-store
access, backups, process inspection and journal access. Never put secrets in CLI
arguments, shell history, tickets or screenshots; disable shell tracing before
loading them. `GRADUATE_EMAIL_OPERATOR_ID` is a current active admin/manager's
numeric ID, set only in an authorized protected operator process. It is not a
password or a substitute for protecting shell access. No HTTP parameter supplies it.

`GRADUATE_EMAIL_BASE_URL` is the independent canonical HTTPS origin, with no
credentials, query, fragment or path except `/`. Do not infer it from request Host,
Google configuration or forwarded input. Production rejects HTTP; local-only
loopback HTTP remains for the synthetic harness. Code/limit keys must each contain
at least 32 bytes of independent cryptographic randomness, differ from each other
and from SECRET_KEY_BASE. Obtain them through the secret store. Missing/invalid
keys/control fail closed. Runtime never recreates a deleted control singleton.
Key rotation is a reviewed operation: disable first (advance generation), replace
secrets consistently on all web/workers, restart, then separately authorize enable.
Never restore an older control/generation from a backup.

Configure one canonical approved sender, approved SMTP host/port and explicit
`starttls` or `tls`, with peer certificate verification. Supply approved
`plain`, `login` or `cram_md5` authentication and both username/password together.
The implementation permits an unauthenticated configuration for an approved
restricted university relay, but this is not evidence of mail-owner approval.
Prefer approved authenticated TLS transport. No credentials in this repository.
Open/read timeouts are3 s; total delivery deadline10 s; no SMTP debug output. The
standalone authentication mail builder raises errors, renders in worker memory,
addresses exactly one approved recipient, has no contact-list/default recipient
and avoids ActionMailer payload instrumentation. General application SMTP behavior
is unchanged. Verify trusted time synchronization, UTC, primary DB routing, actual
MySQL CHECK enforcement/collation and2 s lock deadlines before activation. HTTP
budget is5 s. These are local defaults, not measured QA performance.

## Commands and control behavior

From the reviewed release under the unprivileged app user with its protected
environment and `RAILS_ENV=production`:

```bash
bundle exec rails graduate_email:status
bundle exec rails graduate_email:enable
bundle exec rails graduate_email:disable
bundle exec rails graduate_email:cleanup
```

Enable/disable require `GRADUATE_EMAIL_OPERATOR_ID`; the active admin/manager is
rechecked under the control lock. Enable also requires valid origin/keys/transport.
Disable remains usable when origin/keys/transport break and increments generation
every time, including when already off. Missing/unreadable control rejects commands;
restore only through an approved repair preserving monotonic generation. Enable
retains the latest generation. Old sessions/cookies, approvals and codes never
revive; existing connections need fresh codes, pending approvals need FGS reissue.
Transition and issuance serialize using short primary transactions. An already
authorized response or SMTP call can finish; stale mail cannot authenticate.

Success output is JSON with enum/count fields only; rejection is
`{"result":"rejected"}` and exit1. Status is read-only and reports authoritative
control/generation, configuration readiness, OTP/notice retained jobs, oldest age
in seconds, failed jobs, failed/abandoned notices, challenge/cooldown/limit counts.
`notice_stale_queued` and `otp_stale_queued` count security notices and real OTP
challenges still `queued` at least 60 s after creation. No worker has claimed them,
including when their job row is already gone. Queued notices persist until handled.
Queued OTP rows stay counted until cleanup removes them 24 h after expiry.
It prints no operator/student IDs, addresses, handlers, URLs or exception messages.
A safe status is not a health/approval check of the actual relay or procedure.
Cleanup needs no operator ID, never enables and is safe while disabled.

## Workers and scheduled retention

Install nothing until the separate deployment approval. Templates are in
`config/deploy/graduate-email-worker.service`, `graduate-email-cleanup.service`
and `graduate-email-cleanup.timer`. Replace every release/user/env placeholder,
verify the installed Ruby/bundle PATH and filesystem access, and run the service
parser against the resolved files. The template uses `/usr/bin/env bundle`;
set an owner-reviewed PATH or absolute executable in the installed copy. Do not
assume `/app`, the development container or any QA hostname is a production path.

Install two worker copies, `graduate-email-worker-a.service` and
`graduate-email-worker-b.service`. Each runs the installed foreground
`bundle exec rake jobs:work` with
`QUEUES=graduate_email,graduate_email_notice` and `GRADUATE_EMAIL_WORKER=1`.
The installed delayed_job4.1.13 task supports comma-separated `QUEUES`.
Neither process consumes default/unrelated queues. Both queues must be consumed;
OTP retained cap500 and distinct notice reserve50 include locked/failed rows.
`QUEUE=graduate_email` alone is incorrect. Do not use `jobs:clear`, a default worker,
retry abandoned claims or edit job handlers to regenerate mail.

A dedicated worker refuses to start unless its own process has valid origin, code
and limit keys and a valid sender/SMTP transport. The check runs when the worker
starts, after all initializers. It runs before any job is reserved or any stale lock
is cleared, and reads no control or feature state. A disabled feature therefore
still lets a configured worker deliver queued security notices. The refusal is the
fixed line `Graduate worker delivery configuration rejected` and a non-zero exit;
no configuration value is printed. Queued OTP and notice jobs remain unchanged. The
template's `Restart=on-failure`/`RestartSec=5` repeats each refused start. systemd
stops retrying (`failed`) only if more than `StartLimitBurst=10` starts fall within
60 s, so expect a recurring auto-restart and failure records rather than a running
worker. Correct the worker's protected environment file (it can differ from the
operator's), then restart it, using `systemctl reset-failed` if it stopped. The enable
command's configuration check covers only the operator process; it does not prove
the workers' configuration.

If configuration is unavailable to a job anyway (for example a default worker or
standalone run), nothing is silently consumed. A queued security notice becomes
`failed`, shown to staff as failed with no automatic retry, and logs
`graduate_email notice_unconfigured`. A queued real OTP challenge becomes `failed`
without generating a code, consuming an approval or creating a session, and logs
`graduate_email delivery_unconfigured`. The graduate can request a new code. Neither
case is retried automatically.

The dedicated role sets backend maxrun 30 s/maxattempts1/destroy-failed, enabling
stale lock reclamation after 30 s. Payload state is independently single-claim:
queued jobs survive restart; claimed/sending OTPs and claimed notices never
regenerate/resend after a crash. Explicit fresh request is the graduate's recovery
for ambiguous mail. Successful jobs delete immediately. No exactly-once SMTP claim.

Systemd templates use Restart=on-failure, RestartSec=5, TimeoutStopSec=40,
control-group termination, private tmp, umask0077, no new privileges, read-only
system and restricted writable log/tmp. Stop both and join their process groups
before maintenance. Journal backend output is suppressed with QUIET and a null
Delayed logger; only fixed heartbeat/error enums are emitted by the role. Review
Rails/APM settings too; never enable SMTP/SQL payload debugging. Worker heartbeat
is checked per process on idle loops and after each job, with output rate-limited
to once per 30 s. The 30 s maximum job runtime bounds the interval while busy;
this is a progress callback, not a separate timer. The journal's timestamps and
systemd unit identity distinguish workers without application identifiers.
An absent heartbeat for90 s requires inspection; a heartbeat alone does not prove
SMTP progress. Monitor both unit states, status counts/oldest and failures.

Hourly timer invokes bounded `graduate_email:cleanup`; monitor its exit code and
last successful `result=ok` JSON journal record/time. Alert through existing approved
monitoring if no success in2 h, OTP queue>250, oldest>60 s, either dedicated worker
fails/loses heartbeat or logs the worker configuration rejection, any SMTP
delivery_failed/delivery_unavailable/delivery_unconfigured/notice_unconfigured/worker_error,
new failed/abandoned notice, or `notice_stale_queued`/`otp_stale_queued` above 0. Status exposes retained failures, not a lifetime
counter after deletion. Journal aggregation must count fixed outcome enums only,
with no mailbox/IP/student labels or per-request permanent DB rows. No new external
notification service is configured. Bound monitoring retention using existing policy.

Cleanup uses at most200 batches of 500 per category per invocation, each a fresh
short transaction with the bounded control lock.100,000 events/category exceeds
maximum hourly event ingress93,600 (120 sends/minute *3 events +300 verifies/minute
*4 events, times60). Hourly operation and observed throughput are activation gates;
a backlog can require repeated invocations. Count output is deletions in this run,
not an assertion that no backlog remains. Timer's300 s timeout bounds process life;
interrupted runs are safe to repeat. External QA must measure duration/DB contention.

- Real/noop challenges: remove at24 h past expiry, all delivery states included.
  Audit challenge FK becomes null; policy event/outcome/generation survives.
- Admission/limit events: remove at2 h, preserving keys associated with cooldowns
  until2 h after that cooldown expires. Expired cooldowns remove after 2 h.
- Expired server sessions: remove at24 h past expiry for either method; never remove
  current sessions or mappings and never restore old access.
- Own queue rows: inspect at24 h age in bounded batches. Remove missing/eligible
  expired targets; preserve fresh locks, live targets and queued notices. No unrelated
  queue is touched. Abandoned claims remove after retention without execution.
- Notices: terminal rows24 h after update, abandoned claimed rows24 h after claim.
  Queued notices stay for restart. Approvals/connections/audits have no automatic
  retention schedule until university authorization; ordinary revocation retains
  history. Existing authorized student destruction still cascades owned rows;
  every deleted audit reference becomes null, including the staff actor reference.

For capacity, reserve two DB connections per worker (template setting), the web
pool's configured maximum and one cleanup pool of 2, plus existing jobs/maintenance
and DB headroom. At a web pool of 5 that is at least 11 connections before other
consumers; do not assume a single shared pool of 2 covers web plus two workers.
Use the actual process/thread inventory and primary max_connections at QA.

`docker-compose.graduate-email.yml` is an optional standalone opt-in profile using
an existing reviewed app image, unprivileged UID:GID and protected environment file.
It creates two dedicated workers only, with no web/DB/seeds/migrations. Its temporary
log/tmp mounts are private 0700 and owned by the selected process UID/GID. Set
`GRADUATE_EMAIL_UID` and `GRADUATE_EMAIL_GID` separately to positive decimal
numbers (no leading zeroes, names or root IDs). The same values select the process
user and all three tmpfs owners. Startup rejects invalid or mismatched identities
before loading Rails. Verify mkdir/write/read/delete on `/tmp`, `/app/tmp` and
`/app/log` as that configured user, then foreground start/progress/stop using the
resolved settings. Root workers and broader permissions are not a workaround.
Fixed stdout enums use bounded local logging. Configure
image/network/DB resolution with the owner and schedule hourly cleanup separately.
Do not run the repository's default web compose startup for this feature.

## FGS staff procedure

Use the named approved identity/lost-mailbox procedure above before touching real
records. Verify the existing student's identity and exact individual mailbox through
the approved contact channel. Do not infer access from contact fields or a matching
Google email. Confirm the normalized recipient displayed by ETD, enter it a second
time and explicitly confirm identity verification. No lists or shared/multi-address
fields. The invitation token is shown once, expires48 h and authorizes enrollment
intent only. Provide it through the approved verified-contact channel. ETD does not
email an invitation. Keep it out of screenshots, tickets, referrers and logs.

Staff turnover: a **pending** approval works only while its approving staff member
is still an active, unblocked administrator or manager. This is checked when the
invitation is opened, when each code is sent and when it is redeemed. If that person
leaves or changes role, another authorized staff member must reissue the pending
approval after verification. A **verified** connection belongs to the student.
Its recorded approver is historical audit information only. Blocking or demoting
that staff member later does not stop returning sign-in, existing sessions or
Google. Revoke the connection explicitly if access must end.

Approvals and connections keep a restrictive database reference to the approving
staff account (`approved_by`), so that account cannot be deleted while those
records are retained. Block or demote departed staff instead of deleting them.
Deleting them would require an authorized retention decision for those records,
which is still pending above. Policy audit events are retained, and any audit
reference to a deleted user becomes null.

Cancel a mistaken or unreceived pending approval; reissue only after verification.
Reissue supersedes prior pending email approval; it does not revoke Google or change
ordinary contacts. Graduate opens the invitation, selects Send code and enters the
code in the same browser. Opening the link never sends mail. Code is six digits, including leading zeroes, valid5 min from
request including queue time, with at most5 failures. Resend is explicit and limited.

Lost mailbox, suspected compromise/reassignment, or address replacement requires
FGS identity verification again through the supplied recovery procedure. Pending
replacement preserves old access until verification atomically switches the mapping,
revokes old email sessions/challenges and queues a notice only to the old address.
The notice contains no new mailbox, code or invitation. Confirm connection state
and notice state on the staff screen. Failed/unknown notice does not undo replacement;
escalate via the approved owner/contact channel, never auto-retry an abandoned notice
or reveal the new mailbox to the old one. A full notice reserve can reject replacement
without changing old access; involve operations rather than deleting live rows.

To revoke, select the existing student's connection and explicitly confirm revocation.
Verify pending approvals/challenges/email sessions lose access. Separately linked
Google remains. Blocking the student revokes all graduate methods; unblocking restores
nothing. Ordinary contact edits never change authentication. Student sessions cannot
approve, impersonate staff or self-link Google through PPY.

This is single-factor email access with phishing, compromised/reassigned mailbox,
FGS verification mistakes, delays and shared-budget exhaustion risks. Google and FGS
support remain alternatives. Do not claim NIST assurance: the approved design cites
[NIST SP800-63B-4](https://pages.nist.gov/800-63-4/sp800-63b.html), which excludes
email as an out-of-band authenticator, and the
[OWASP handling guidance](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html).
These are the original design sources, not a fresh guidance review.

## Rollback and separate release approvals

QA evidence, production deployment approval and email activation approval are
separate. No local pass supplies any of them. Before activation require reviewed
migration/rollback, FGS readiness, controlled-mail/proxy/cookie checks, both workers,
cleanup restart, monitors and signed QA evidence from the verification guide.

Rollback first disables using an authorized operator (advances generation), then
stops both dedicated workers, then deploys compatible code. No destructive down
migration or old-generation database restore. Pre-email session code assumes a
non-null Google identity FK and cannot read email session rows: revoke **and remove**
email server-session rows through an approved bounded migration/maintenance procedure,
or deploy a reviewed compatibility bridge before reverting. Revocation alone does
not make nullable Google rows compatible with old readers. Preserve Google/PPY,
connections/history/policy audit and the newest generation. Validate the rollback
release against the migrated schema. Deployment/activation require separate owner
approval; every git push also requires explicit approval.
