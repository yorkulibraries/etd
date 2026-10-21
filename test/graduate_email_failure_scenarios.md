# Graduate email failure scenarios

Written before implementation. Each later test cites its requirement IDs.

- F01: Explicit staff approval and address confirmation.
- F02: Invitation secrecy, single use and 48-hour expiry.
- F03: Canonical address equality without inferred aliases.
- F04: Independent unique active student and address mappings.
- F05: Six digits, expiry and replay denial.
- F06: Five failed attempts per challenge.
- F07: Shared aggregate send and verification budgets.
- F08: Cross-browser and cross-purpose separation.
- F09: Delivery crashes and ambiguous acceptance.
- F10: Duplicate durable queue claims.
- F11: Atomic challenge and job rollback.
- F12: Disable generation and issuance races.
- F13: Dormant browsers never revive old generations.
- F14: Blocked/inactive students and inactive approvers.
- F15: Logout, session rotation and expiry.
- F16: Staff and impersonation boundaries.
- F17: Downloads and student ownership.
- F18: Independent Google and Passport York behavior.
- F19: Unknown-path enumeration and bounded admission.
- F20: Recovery, replacement and revocation.
- F21: Secret-free screenshots, HTML, logs and reports.
- F22: Cleanup, persistence and process restart.
- F23: SMTP, proxy and secure cookies.
- F24: Separate QA procedure and production gates.

Task 1 runner/probe isolation scenarios, specified before implementation:

- Reject wrong adapter, wrong MySQL database, missing confirmation, query/fragment, or alternate SQLite path before connecting. Never expose URL or connection exceptions.
- Replace inherited TEST_DATABASE_URL in every child; verify actual adapter/database in probe and test harness. Confine SCHEMA and snapshots to root tmp.
- Preserve first baseline snapshot across repeated checks, including every queued column and original Google digest/expiry. Check fresh and upgrade up/down/up.
- Remove the database method default in a disposable transaction to prove the frozen/raw insertion fails rather than being hidden by upgraded models.
- Commit job in one process and read it in another; rollback retains neither challenge nor job. Never execute sentinel payloads.
- Exercise each audit FK separately and real manager deletion; preserve policy columns and unrelated references.
- Assertion and error hooks must touch neither browser nor files, even if URL/form/mail contain sentinels and HTML capture is enabled.

Task 4 delivery isolation scenarios (written before delivery implementation):

- D01 / F05 F09 F10: Persist/reload the real opaque-ID job; queued is unverifiable. Single claim commits six zero-padded random digits as contextual CODE_KEY HMAC only, claimed is unverifiable, only original immutable memory claim authorizes sending. No approval consumption/session issuance.
- D02 / F05 F13 F19: Unknown/noop never generates or builds mail. Creation + five minutes is immutable even with queue delay. Disabled/re-enabled pending jobs never send.
- D03 / F09 F10 F22: SIGKILL isolated real worker before claim commit, after claim commit, after authorization, after RAM SMTP acceptance, after sent commit. Restart and explicitly enqueue same ID; <=1 accepted message, no regeneration of claimed/sending. Only current sending/sent may match delivered code.
- D04 / F12 F14 F20: Before authorization reject changed generation, blocked/inactive student/approver, revoked/consumed/expired approval, missing/changed mapping, connection revocation, same-browser replacement, challenge expiry/consumption/invalidation. Conditional success/error cannot overwrite terminal or old-generation state.
- D05 / F09 F18 F23: During stalled RAM transport other database sessions complete disable, direct model block, HTTP controller block, same-browser resend and Google issue within five seconds. Render/transport/diagnostic callbacks assert zero open transactions; no sleeps establish race order. Ten-second deadline test proves bounded stall.
- D06 / F09 F21: Explicit SMTP/render error clears digest conditionally, never retries or consumes approval. Retry conditional failure once on fresh database transaction after database failure; ambiguous sending remains conservative. Actual DEBUG Rails log subscribers, notification subscriber, notifier hook and backend last_error contain no sentinel code/token/mailbox/raw cause. Do not globally mute other mailers/loggers.
- D07 / F03 F21 F23: Own boot-safe SMTP config fails closed on invalid sender/host/port/TLS/auth without feature-table queries; preserve general mail config. Exactly one canonical recipient and approved sender, no CC/BCC/contact helpers. Dedicated class builders return text Mail::Message with no ActionMailer dispatch/instrumentation. <=3 second open/read and ten second total deadline, worker 30 seconds.
- D08 / F20 F21: Seed notice directly, identifier-only separate queue and 50 reserve constant; claim once, network outside locks, immutable old recipient only, no code/new address/link. Still send required notice while email control disabled; failure/duplicates never restore access or retry.

Task 4 self-review D07 follow-up, before correction: a frozen ordinary Ruby Time with a non-UTC offset must render the original expiry without in-place timezone mutation. Exercise the real builder in the SMTP configuration integration case.

## Task 7 verification boundary (before implementation)

F27: Clean capture allowlist rejects unknown names/routes/headings, entered code,
query/fragment URLs, invitation/generated-token DOM, token-shaped values and hidden
secret inputs. Automatic and Google token capture suppression remains unconditional.
F28: Report/manifest permits only static source-known identities, categories/counts,
fixed metadata and hashes. Reject symlinks, unlisted files and sentinel-bearing bytes
without printing the match. Never persist raw output, DOM, mail, cookies or URLs.
F29: Runner reuses guarded storage fresh and seeded upgrade up/down/up, inherits both
identical DB URLs, honors numeric seed, binds pre/post source and publishes only scan
approved artifacts. Reject malformed adapter/seed and stale or modified sources.
F30: At desktop 1440x1000/mobile 390x844 clean login/send/error/expired/revoked,
connection/staff confirmation and notice states fit, have accessible names and error
associations and support keyboard. A code submit clears input before capture.
F31: Disable/re-enable invalidates dormant browser session/code/enrollment and a
paused actual persisted worker. Fresh sign-in works; no old job sends. Stop/join
workers and clear RAM mail in ensure before truncation.

## Task 7 R1 sealed package boundary (before fix)

F32: General browser runs retain all clean DOM/layout assertions but never call
the image driver or write files without the runner's explicit capture directory.
An assertion failure after a clean screen cannot change the sealed package.
F33: Explicit capture rejects an already sealed destination before the image
driver. Named reruns use a validated single path component under verification;
invalid/traversal names fail closed. A dedicated unsealed runner still writes all
18 PNGs and checks their actual widths.
F34: On BOTH adapters run the exact CI runner, broad application and general
browser phases, then scan. Compare every sealed file including manifest before
and after. Run a disposable controlled failing browser after a clean capture,
require nonzero exit and unchanged package, then scan. A separate tampered copy
must still fail publication scan; never reseal a stale successful result.

## Task 8 operations and retention (written before operations code)

- O01: missing/short/equal keys, malformed/non-HTTPS canonical production origin, missing control or relay prerequisites must refuse enable/admission; disable remains available when configuration breaks. Missing/malformed/stale/blocked/student/non-manager operator refuses transitions with enum-only output.
- O02: status/cleanup never enables; status reports enum/counts only, no identifier, mailbox, job handler, exception or secret. Repeated disable increments generation; re-enable cannot revive cookies, challenges or approvals.
- O03: cleanup preserves live and recently expired real/noop challenges, current mappings, both current session methods, approvals/connections/history and active/recent limits/cooldowns. Expired challenge+24h, event+2h, cooldown expiry+2h, terminal/abandoned notice+24h, expired session+24h boundaries are exact and idempotent.
- O04: successful policy audit survives challenge deletion and every nullable FK deletion, including authorized student destruction. No unknown/rejected/noop creates a target or policy audit.
- O05: batches <=500, bounded transaction count per invocation, correct FK order and disabled operation; interrupted cleanup can repeat safely. Own queues only, unrelated jobs remain. Fresh locks and queued notices survive; expired abandoned claims never send/regenerate.
- O06: multiple synthetic windows of unique unknown addresses/IPs, IP/global saturation, cleanup between windows stabilize at rate-times-retention bounds. Stopped cleanup still caps retained OTP at500/notices50 and saturation preserves a live challenge.
- O07: real guarded CLI subprocess disables against concurrent session issuance in both lock orders; old generation never validates after enable. No network or process wait inside production transaction.
- O08: notice transport/render exception containing sentinel/recipient/code remains secret-safe; failures never undo replacement. Metrics are fixed enum/count-only, heartbeat/oldest/failed/cleanup success safe.
- O09: two real foreground installed jobs:work processes, each consuming QUEUES=graduate_email,graduate_email_notice, are killed/restarted with queued durable work and fake SMTP. Both queues progress, unrelated default sentinel remains; killed claimed OTP and notice are never retried/regenerated. Join and clean every child/transport.
- O10: production cookie retains _etd_session and explicitly Secure/HttpOnly/Lax. Service templates have foreground worker, maxrun30/attempt1, stop40/restart5, protected env/unprivileged user, safe journaling, two workers plus web DB sizing and bounded hourly cleanup. Parser unavailability is an external QA limit, never a local pass.

## Task 8 fix round 1 (recorded before the corresponding fixes)

- O11/R1: resolve both Compose workers with numeric nonroot UID/GID. Each 0700 tmpfs root must match that identity and permit mkdir/write/read/delete as that actual user. Reject zero, malformed and mismatched identities before foreground work. Retain read-only root, dropped capabilities, no-new-privileges and bounded safe logging. In a disposable container with those resolved settings, run actual foreground workers with RAM transport, prove progress on both dedicated queues, unrelated queue preservation, queued restart and claimed no-retry; stop/join all workers.
- O12/M1: no-DB installed Delayed Job lifecycle, 100 synthetic one-second jobs followed by 100 idle seconds. Heartbeats must cover busy and idle progress, be separated by at least 30 seconds with no gap over 31 seconds in this workload, contain only the fixed enum and remain bounded. An ordinary worker must retain defaults and emit no graduate heartbeat.
- O13/M2: preserve the historical package and binding. Record the historical claimed SHA and independently observed current whole-package SHA, prove the diff section equals the original committed diff, and explicitly leave cause/time unknown.
