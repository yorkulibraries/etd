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
