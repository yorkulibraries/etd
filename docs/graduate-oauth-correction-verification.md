# Graduate OAuth correction

Date: 2026-10-06
Branch: graduate-authentication
Status: patched and verified locally; not deployed or pushed.

Provider selection changed on 2026-10-08: the user requested Google-only authentication. This report records the earlier two-provider correction and its historical results. Current configuration is described in [graduate authentication setup](graduate-authentication-setup.md).

## Scope

Only Google/Facebook authentication, account linking, callbacks and graduate OAuth sessions were corrected. The inherited thesis and embargo permission findings were excluded at the user's request. Passport York and staff support retain their existing sign-in behavior.

## Corrections

- Graduate sessions have a fixed 12-hour lifetime and a server-side revocation record. Only the random token's digest is stored in the database.
- Logout and same-browser reauthentication revoke the previous graduate session. Blocking a Student revokes all graduate sessions, including dormant browsers. Unblocking does not restore them.
- Missing, expired or inconsistent graduate credentials cannot supply Passport York linking proof.
- Google sends S256 PKCE and a fresh nonce. The callback requires matching identity-token claims and the same subject as the returned user information.
- Both providers accept only the registered server-side code callback. Facebook authorization options are fixed and its state protection remains enforced. Undocumented Facebook web PKCE support is not assumed.
- Invitation consumption, account linking and graduate-session issuance complete in one transaction. Expired graduate logout keeps the graduate login destination.

## Verification

| Check | Final result |
| --- | --- |
| Full Rails regression with test job queue | 305 tests, 2,411 assertions, passed |
| Repeatable graduate request checks | 77 tests, 1,571 assertions, passed |
| Graduate browser flows | 7 tests, 115 assertions, passed |
| Final MySQL session/lifecycle checks | 20 tests, 540 assertions, passed |
| MySQL session migration | Up, down, up passed |
| Ruby syntax and diff whitespace | Passed |

New failure cases and request checks were written before their corresponding corrections. Real provider exchanges were simulated at the network boundary. Private application requests, session cookies, CSRF checks and browser interactions used the ordinary Rails stack.

The plain full-suite command encountered an existing async export-job/SQLite cleanup lock. Those interrupted runs are not passing evidence. The passing full regression used Rails' test job queue and loaded the fake OAuth configuration before application boot. Application export code and the common test harness were not changed.

## Repeatable checks and artifacts

With the existing local application container and updated bundle:

```sh
docker exec etd-graduate-auth bash script/verify_graduate_authentication
```

This writes `tmp/graduate-authentication-verification.txt`, browser screenshots and the authorized-download checksum. Additional logs are under `tmp/oauth-correction/`: `parent-full-rails-queued-final.log`, `repeatable-runner-final.log`, `mysql-verification.log` and `mysql-final-session-lifecycle.log`.

The final full regression was repeated with the previously locked run's seed, 27551, using the test job queue and correct OAuth boot configuration. It passed all 305 tests with 2,411 assertions. Its log is `tmp/oauth-correction/parent-full-rails-seeded-final.log`. The exact full-suite command is saved in `tmp/oauth-correction/full-regression-command.sh`, runnable inside the application container. `tmp/oauth-correction/verification-manifest.json` records the branch, HEAD and hashes of the verified application and test files.

## Deployment requirements

Apply `20261006130000_create_graduate_sessions.rb` with the existing deployment migration process before restarting the application. Existing graduate OAuth cookies require a fresh provider sign-in. Verify real Google and Facebook login, callback registration, Apache Passport York header handling, private-upload denial, HTTPS and cookies on staging before activation.

This closes the OAuth controls checked here. It is not a clean bill of health for the whole application, and the excluded thesis/embargo findings remain.
