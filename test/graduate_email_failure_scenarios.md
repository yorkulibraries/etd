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
