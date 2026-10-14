# Graduate OAuth session failures

Written before the session correction and its application or migration changes.

The regression requests use actual Passport York headers, the existing mocked
provider boundary, real CSRF form submission and the private `/my/details`
request. Cookie replay uses the exact encrypted cookie returned by Rails.
Only compatibility cases construct a Rails-encrypted legacy cookie.

1. A copied graduate cookie still reads private details after logout.
2. Requests extend a graduate login beyond its absolute 12-hour expiry, or the
   login remains valid at the exact expiry boundary.
3. A legacy graduate cookie without a session token, a removed session record,
   or a token whose digest no longer matches retains private access.
4. A server session bound to another identity or another Student is accepted.
5. Blocking the Student fails to revoke a saved cookie; unblocking restores it.
6. Unlinking through the existing PPY connection route is prevented by the new
   foreign key, or leaves a saved graduate cookie usable.
7. Signing in again in the same browser leaves its previous session usable.
8. Rotation or logout in one browser invalidates another browser's valid login.
9. Moving from graduate login to PPY leaves the previous graduate cookie usable.
10. PPY login/linking creates graduate sessions, changes existing logout routing,
    or acquires the graduate 12-hour expiry policy.
11. Legacy PPY cookies and active staff support of a blocked Student are rejected
    merely because no graduate token or authentication source exists.
12. Session tokens or provider credentials are stored in database columns or
    audits, or the named graduate session token parameter is logged unfiltered.
13. A legacy graduate cookie lacking its authentication source is mistaken for
    legacy PPY despite retaining graduate markers; a cookie lacking its user ID
    leaves its graduate credential live instead of clearing and revoking it.

Preserve the existing behavior when providers are disabled: configuration gates
new provider requests. This bounded correction adds no new configuration-based
revocation policy without evidence that such a policy is intended.

Runtime coordination: do not run Rails tests until the parent grants the runtime
lock. Use the existing Docker Ruby 3.1.4 runtime, an isolated test database and a
temporary schema path. Never dump SQLite schema over the canonical MySQL schema.
