# Graduate email code sign-in

## Agreed outcome

Graduates who have lost Passport York access can access their existing ETD student record using an emailed one-time code. Google remains an independent alternative. Staff continue to authenticate with Passport York.

FGS establishes the association between the graduate and the student record. A code establishes control of the specific email FGS approved. Contact-email matches alone never grant access or create an account.

## Enrollment

1. An active, authorized FGS administrator or manager verifies the graduate through the existing staff identity-check process.
2. Staff selects the existing student and explicitly approves one individual email address. Existing primary and secondary contact fields can be reference information; neither is automatically enrolled. Both fields can contain multiple addresses.
3. ETD creates a pending approval, recording the student, exact approved address, staff actor, creation time, expiry, and revocation/consumption state. Approval expires after 48 hours, matching the current Google invitation lifetime. A new email approval replaces an older pending email approval for that student without revoking a Google invitation.
4. Staff provides an enrollment invitation through the verified contact channel. Its random, securely digested, single-use token creates enrollment intent only. It cannot establish a student session by itself.
5. The graduate opens the invitation and requests a code sent only to the approved address. Successful code verification atomically consumes the invitation and activates the email connection, then starts the graduate session.

An email connection cannot be activated for an inactive or blocked student. Staff impersonation cannot approve or enroll connections. Approval and challenge validity are checked again when enrollment is completed.

Staff must see and confirm the approved individual address before issuing an invitation. Operating instructions must reference the actual FGS-approved identity verification procedure, including lost-mailbox recovery; its existence or adequacy is not established by application code. Confirm that procedure before QA enrollment with real student records. Canceled and superseded approvals and their challenges cannot activate a connection. The graduate screen explains that the code must be entered in the browser that requested it.

## Returning sign-in

The graduate chooses "Email me a sign-in code", enters the enrolled address, and enters the code in the same browser session. ETD grants access only to the student associated with an active email connection. No account creation or fallback matching against contact fields occurs.

For unknown, disabled, blocked, or unenrolled addresses, ETD returns the same status, screen, and message: "If this address is enabled for graduate sign-in, we’ll send a code." Response timing must not disclose account existence. Codes for different purposes, sessions, identities, or approvals are not interchangeable.

## Proposed security defaults

- Generate six digits with a cryptographically secure random generator; preserve leading zeroes.
- Expire challenges five minutes after creation, including delivery time.
- Permit at most five failed verification attempts per challenge. Apply additional persistent verification limits per connection/address and per IP across replacement challenges.
- Permit one send per address per 60 seconds and five sends per hour. Also limit requests per IP to 20 per hour. Enforce shared, atomic counters across application workers; do not use per-process memory. Revisit thresholds using QA and operating evidence.
- An accepted resend invalidates only the previous challenge for the same browser transaction and purpose. A request from another browser cannot invalidate that transaction's code. Throttled requests leave all existing challenges unchanged, and send limits alone do not prevent verification of an already-issued code. Verification limits still apply. Resends do not reset aggregate limits. Never permanently block the student's account because someone requested or guessed codes.
- Bind challenges to a server-verified browser transaction and purpose. Use CSRF-protected POST requests for sending and verification, HTTPS, and no-store responses.
- Store only a keyed digest of the code, using a dedicated application secret and challenge context. Compare securely. A database-only leak must not permit cheap offline enumeration of the six-digit space.
- Consume successful challenges inside a transaction with locking so concurrent requests cannot both succeed. Recheck current connection, approval, and student state under the relevant locks.
- Rotate the authentication session after verification. Preserve secure cookie settings and existing student-only authorization, expiry, logout, blocking, and revocation behavior.
- Never put codes or invitation tokens into logs, analytics, screenshots, or audit payloads. Codes never appear in URLs.

These are application defaults, not a claim of NIST authentication assurance. Email code sign-in is single-factor access, vulnerable to phishing and mailbox compromise. NIST SP 800-63B-4 excludes email as an out-of-band authenticator.

An attacker can still temporarily exhaust shared address send limits or verification limits. This bounded availability risk is accepted for this version, with independently linked Google access and FGS support as alternatives. Mailbox compromise, address reassignment, mail delays, and mistakes in FGS verification also remain risks.

## Data and integration

Persist an email connection separately from editable contact fields, with student, normalized address, verification time, approving staff, and revocation state. Allow one active email connection per student and one active student per normalized address, enforced in the database. Trim surrounding whitespace and compare addresses case-insensitively; do not strip plus tags or dots or infer mailbox aliases. Reject input containing multiple addresses.

Use a separate active-address mapping with non-null student and normalized-address columns and independent unique indexes on each. Preserve revoked connection history outside that mapping. Creation, removal, and replacement of the mapping and connection state must be atomic. Do not rely on a unique `(normalized_address, revoked_at)` index: nullable columns would allow duplicate active connections. Validate migrations and competing writes on MySQL and SQLite before accepting the implementation.

Persist temporary challenges with connection or pending approval, purpose, browser transaction digest, code digest, expiration, failed-attempt count, and consumed state. Delete expired challenge records through scheduled cleanup after a short operational retention period; retain secret-free audit events separately.

Reuse the graduate session lifecycle and explicitly extend its current Google-only provider and authentication-source assumptions. Keep Google's provider plus UID lookup unchanged. Session validation must identify the authentication method, verify that method's connection is still active, and preserve student role restrictions. Avoid inserting email into Google's stable UID field without an explicit compatible model design.

The implementation plan must cover the existing identity foreign key, session markers, logout, blocking callback, and OAuth-intent preparation. Anonymous graduate redirects must work with email enabled and Google disabled. Email sessions cannot acquire staff privileges, approve invitations, or self-link Google through the Passport York enrollment route. Verify existing protected document downloads as well as page access.

Use a dedicated authentication mailer and template. Send to exactly one approved address, bypassing the contact-mail recipient-list helpers. Ensure codes cannot be exposed through mailer debug output or job arguments. Delivery failures must not consume a code or create a session; delayed mail cannot extend expiration. No automated delivery retries after the challenge expires.

Use a durable background job containing only an opaque challenge identifier. Its single claimed execution generates the code in worker memory, stores the keyed digest before sending, and sends directly through the dedicated mailer without enqueuing plaintext. Expiry remains five minutes from challenge creation, so queue delay reduces the usable time. Recheck current challenge, approval or connection, and feature state before sending. A duplicate job cannot generate or send a second code. On a reported delivery error, mark the challenge failed and unverifiable. On a crash or ambiguous SMTP outcome, do not automatically retry delivery; an already-sent code remains usable only if its stored state permits verification. The graduate can explicitly resend within limits. A delivery failure never authenticates a user or consumes an enrollment approval.

The current repository does not configure a durable production job backend or shared throttling backend. The implementation plan must select and configure both, including worker supervision and secret-free error reporting. Unknown-address and throttled requests follow an equivalent bounded asynchronous request path and identical public responses; delivery outcomes are not disclosed by polling endpoints. Measure timing on QA rather than assuming asynchronous work prevents enumeration.

## Revocation and recovery

FGS can revoke pending enrollment, an email connection, its challenges, and its sessions. Blocking a student revokes all graduate sessions and prevents all code verification. Removing email access leaves a separately linked Google connection intact.

For the first version, lost-mailbox recovery and changes to the sign-in email go through FGS identity verification again. After verification of a replacement address, switch the active connection atomically, invalidate old email challenges and sessions, and notify the old address without sending the new code there. Changing ordinary contact fields never changes authentication access.

## Verification and rollout

Write failure scenarios before application code. Use browser E2E coverage for enrollment and repeat sign-in, unknown and duplicate addresses, wrong/expired/reused codes, cross-browser and cross-purpose misuse, resend and aggregate limits, revoked/expired approvals, concurrent redemption, blocked students, staff boundaries, logout, replacement, and revocation. Prove with two browsers that resends cannot invalidate each other's codes and that send throttling does not stop otherwise valid verification. Include regression coverage for existing Google and Passport York behavior, plus email-only operation.

Produce a repeatable verification report with commands, results, screenshots without secrets, and evidence of the expected student record and access restrictions. Verify desktop/mobile states and controlled-mailbox delivery on QA. Check shared throttling and concurrent consumption with multiple workers, using targeted integration checks where browser timing cannot reliably establish the result.

Ship behind a separate default-off email sign-in control persisted in the shared database, with an enabled state and monotonically increasing authentication generation. Read authoritative state for enrollment, sending, verification, and every email-authenticated request; missing or unreadable state fails closed for email access. Disabling atomically advances the generation and disables access. Approvals, challenges, queued jobs, and sessions carry their issuing generation; older generations can never authenticate or complete enrollment after re-enablement. Existing verified email connections remain enrolled, but require a new sign-in challenge after re-enablement. Pending approvals require FGS reissue. Serialize generation checks and authentication issuance with the control transition so a racing request cannot issue valid access after disable. Google and Passport York remain independent. Test disable/re-enable with a browser dormant throughout the disabled interval and with a paused delivery job.

Apply migrations and validate the deployed mail delivery path, authenticated SMTP transport as appropriate to the university relay, sender authentication, proxy and application token redaction, actual cookies, shared throttling, and public HTTPS routes before enabling QA. Production activation is a separate deployment decision.

## Sources

- OWASP Forgot Password Cheat Sheet, applied to the handling of emailed authentication secrets: https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html
- NIST SP 800-63B-4: https://pages.nist.gov/800-63-4/sp800-63b.html

## Review status

The user approved the overall FGS-approved enrollment and email-code sign-in approach and requested independent review until agreement. Astra round 1 required changes to browser-scoped resend behavior and disable/re-enable semantics. Both objections were accepted and addressed above, with integration, delivery, and operating requirements made explicit.

Following the user's direction to use only GPT-6.1 Sol for further delegated agents, Sol independently reviewed the revision in round 2 and returned APPROVE for implementation planning, with no remaining blocking design gaps. The lead agrees. This is design agreement, not implementation verification or deployment approval.

Carry three nonblocking requirements into the implementation plan: choose aggregate verification counts/windows/cooldowns with atomic enforcement across enrollment and login challenges; define delivery states and crash/race behavior precisely; and use consistent normalized-address equality for database indexes, lookups, and throttling, with deliberate MySQL collation and SQLite parity. These must be resolved before implementing their respective controls.

FGS procedure confirmation, durable workers, shared throttling, and actual QA verification remain prerequisites. No application code, database, or deployment changes have been made. Review evidence and task IDs are recorded in `docs/graduate-email-otp-worklog.md`.
