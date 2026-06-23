# Rails 8.1 Upgrade Baseline

Date: 2026-06-23

## Git

```text
?? docs/
```

## Ruby

```text
ruby 2.6.10p210 (2022-04-12 revision 67958) [universal.x86_64-darwin25]
```

## Bundler

```text
Bundler version 2.3.26
```

## Repo Ruby

```text
3.1.4
```

## Rails Lockfile Version

```text
285:    rails (7.0.8.1)
439:  rails (~> 7.0, >= 7.0.3.1)
```

## Rails Blockers In Lockfile

```text
7:      activemodel (>= 6.0.0, < 7.1)
99:      activerecord (>= 5.0, < 7.2)
168:      actionmailer (>= 5.2, < 8)
169:      activesupport (>= 5.2, < 8)
180:      railties (>= 3.2, < 8.0)
```

## Baseline Verification

Docker Desktop was running, but the Docker client initially failed against API `v1.47`:

```text
ERROR: request returned Internal Server Error for API route and version http://%2FUsers%2Fdndeli%2F.docker%2Frun%2Fdocker.sock/v1.47/info
```

Using `DOCKER_API_VERSION=1.46` resolved the daemon/client issue:

```bash
DOCKER_API_VERSION=1.46 docker info
```

Result: exit 0.

### Docker Build

```bash
DOCKER_API_VERSION=1.46 docker compose build web
```

Result: exit 0. Image built as `docker.io/library/etd-web:latest`.

### Database Prepare

The raw plan command completed but used the Compose default development `DATABASE_URL`:

```bash
DOCKER_API_VERSION=1.46 docker compose run --rm web bundle exec rails db:prepare
```

Result: exit 0.

The test database was then prepared with an explicit CI-style SQLite test URL:

```bash
DOCKER_API_VERSION=1.46 docker compose run --rm -e RAILS_ENV=test -e DATABASE_URL=sqlite3:db/test.sqlite3 web bundle exec rails db:prepare
```

Result: exit 0.

### Test Suite

The raw plan command failed because Compose sets `DATABASE_URL` to the development database while `rails test` runs in `test`:

```bash
DOCKER_API_VERSION=1.46 docker compose run --rm web bundle exec rails test -v
```

Result: exit 1.

Failure signature:

```text
ActiveRecord::EnvironmentMismatchError: You are attempting to modify a database that was last run in `development` environment.
DatabaseCleaner::Safeguard::Error::UrlNotAllowed: ENV['DATABASE_URL'] is set to a URL that is not on the allowlist.
228 runs, 0 assertions, 0 failures, 228 errors, 0 skips
```

The CI-style SQLite test command passed:

```bash
DOCKER_API_VERSION=1.46 docker compose run --rm -e RAILS_ENV=test -e DATABASE_URL=sqlite3:db/test.sqlite3 web bundle exec rails test -v
```

Result: exit 0.

```text
228 runs, 840 assertions, 0 failures, 0 errors, 0 skips
```

### System Tests

The first system-test attempt failed because the `chrome` service was not running/resolvable for `SELENIUM_REMOTE_URL=http://chrome:4444`:

```bash
DOCKER_API_VERSION=1.46 docker compose run --rm -e RAILS_ENV=test -e DATABASE_URL=sqlite3:db/test.sqlite3 web bundle exec rails test:system TESTOPTS="-v"
```

Result: interrupted after repeated `SocketError: Failed to open TCP connection to chrome:4444`.

The Chrome service was started explicitly:

```bash
DOCKER_API_VERSION=1.46 docker compose up -d chrome
```

Result: exit 0.

The system-test suite then passed:

```bash
DOCKER_API_VERSION=1.46 docker compose run --rm -e RAILS_ENV=test -e DATABASE_URL=sqlite3:db/test.sqlite3 web bundle exec rails test:system TESTOPTS="-v"
```

Result: exit 0.

```text
46 runs, 119 assertions, 0 failures, 0 errors, 0 skips
```

### Asset Precompile

```bash
DOCKER_API_VERSION=1.46 docker compose run --rm -e RAILS_ENV=production -e SECRET_KEY_BASE=dummy -e DATABASE_URL=sqlite3:db/test.sqlite3 web bundle exec rails assets:precompile
```

Result: exit 0.

Generated SQLite schema drift from `db:prepare` was reverted; no application files changed during baseline verification.
