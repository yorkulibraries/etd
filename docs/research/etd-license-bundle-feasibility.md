# ETD licence-bundle automation feasibility

Date: 2026-08-30

## Conclusion

Yes. The two text licences can be attached automatically so that YorkSpace displays them under **License bundle** instead of **Original bundle**. For YorkSpace's DSpace 7.6.5 deployment, the reliable route is a post-deposit REST operation:

1. create a `LICENSE` bundle on the item if it does not exist; and
2. upload `license.txt` and `YorkU_ETDlicense.txt` directly to that bundle.

The current SWORD media-upload route is not suitable for these files. DSpace's own 7.6.5 configuration says that individual SWORD media uploads are stored in both the `SWORD` and `ORIGINAL` bundles. That explains why licence files added through the current deposit appear as normal item files.

No production YorkSpace records were modified. Subsequent validation modified only dedicated synthetic staging records.

## Implementation status

Staging test item: https://ys.library.yorku.ca/items/49afbf5d-d877-42a4-8136-a4e3253f11b7/full.
The browser-deposited synthetic item has a generated `license.txt` (1,878 bytes). Its text is exactly the packaged canonical licence with CRLF converted to LF and a final newline added. The manifest accepts this one verified existing variant by exact size and hashes, preserving the accepted deposit licence. Arbitrary whitespace normalization or different legal text is not accepted. New uploads still use the original canonical bytes. The canary download check accepts the verified SHA-256 variant too.

Implemented locally on 2026-08-31, with reliability fixes on 2026-09-16. On September 16 the Rails REST canary uploaded the missing ETD licence to the staging item's LICENSE bundle, preserved the existing licence, verified both downloaded hashes, confirmed a no-op repeat and unchanged non-LICENSE bundles, and was checked on the full item page.

The full SWORD-to-job test on September 17 remains blocked: metadata creation returned item `a6a3d5ff-1f38-4975-99be-7f513f829016`, but SWORD media upload returned HTTP 500 before the licence job was created. An authenticated inspection found only the SWORD XML, not the synthetic thesis file or LICENSE bundle. Do not redeposit or delete that partial record until reconciled. Backend logs are required to establish the cause; it is not proven to be a server-only defect. Production activation and the July backfill remain on hold pending end-to-end validation.

`script/validate_staging_sword_pipeline.rb` is a local-development-only harness targeting the staging collection explicitly. It defaults to a local rehearsal. Its apply mode records a one-shot journal and refuses repeat deposits. It does not configure deployed Rails settings or replace the deployment recovery worker.

For an ETD staging deployment, configure both SWORD and REST endpoints to `ys.library.yorku.ca`, apply the migrations, and configure the recovery worker before a synthetic-only export. The export's `production_export` flag means finalized-export mode, not a hostname safeguard: verify the saved endpoints and selected thesis IDs explicitly. Do not export queued student records during validation.

The implementation consists of:

- a DSpace 7 REST client that handles CSRF-cookie acquisition, password login, bearer authentication, bundle reads/creation, and one-file multipart bitstream uploads;
- an idempotent service that verifies the two approved local payloads, refuses conflicts, creates or reuses `LICENSE`, uploads only missing files, and re-reads server state after each successful write;
- a per-item `DspaceDeposit` record and independent `DspaceLicenseBundleJob`, so a REST failure cannot change the successful SWORD result or trigger a second SWORD deposit;
- a production/complete-deposit handoff in `DspaceExportJob` that extracts the item UUID only from recognized DSpace item/SWORD edit URLs;
- a dry-run-first `dspace:licenses:backfill` task for UUIDs in CSV column A; and
- the two payloads copied byte-for-byte from the supplied known-good YorkSpace record and guarded by size, MD5, and SHA-256 values.

### Configuration

Set **DSpace REST API URL** on the DSpace settings page. For YorkSpace, the value is:

```text
https://yorkspace.library.yorku.ca/server/api
```

The implementation reuses the configured live DSpace username and password. Confirm that this account has REST permission to add bundles and bitstreams before any write run.

### Recovery and deployment

Run `bundle exec rails db:migrate` before enabling the REST URL. Run `bundle exec rake dspace:licenses:worker` under the deployment process supervisor alongside the web process, with the same environment and database. Restart it automatically on failure. Alternatively schedule `bundle exec rake dspace:licenses:recover` every minute using the deployment's scheduler. Do not rely only on Rails' in-memory async queue.

The database is the durable work list. The worker recovers pending records, interrupted running records, and failed records whose five-minute retry delay has elapsed. Each record gets at most five attempts; conflicts, exhausted attempts, and permanent permission errors become `review_required`. Inspect these records and `last_error`; after correcting the cause, an operator can reset `license_status` to `pending`, `license_attempts` to `0`, and `license_retry_at` to `nil`. This retries only licence attachment, never SWORD deposit. Missing or ambiguous receipt UUIDs remain visible in the export log and require reconciliation with the repository item.

MySQL named locks serialize each item's job and backfill operations across processes sharing the database. They are released on connection termination, so a crashed worker can be recovered. All writers for this application must use the same MySQL server. Repository staff or other applications do not participate in this lock. Reruns always inspect current remote state before writing; a timeout after a successful upload is reconciled on the next run.

Licence writes and the recovery worker require MySQL; SQLite does not implement `GET_LOCK`. CI retains both database passes: SQLite tests licence service/job behaviour with a test-only lock stub and skips the MySQL concurrency integration test. The MySQL pass uses real locks throughout, including cross-connection exclusion, nested acquisition and release after exceptions. No runtime no-op lock fallback is provided.

Authenticated collection reads cover restricted records and follow pagination. Public reads remain possible when credentials are absent. Receipt identifiers are extracted from parsed Atom links and IDs, and conflicting identifiers are rejected. Exact licence bytes are protected against Git line-ending conversion.

### Single-record validation

The selected canary is the first record in the supplied July CSV, `007f52fc-ce9c-4151-a21d-95ec3432b9ff`. A fresh public check on 2026-09-16 found no LICENSE bundle. Configure the credentials through app settings or the deployment secret environment; do not place passwords in command history.

```sh
CSV_PATH=/path/to/July2026_ETDs_master.csv \
ITEM_UUID=007f52fc-ce9c-4151-a21d-95ec3432b9ff \
DSPACE_REST_API_URL=https://yorkspace.library.yorku.ca/server/api \
RESULTS_PATH=/path/to/dspace-license-canary.jsonl \
APPLY=true CONFIRM=ATTACH_LICENSES \
bundle exec rails runner script/validate_dspace_license_canary.rb
```

Omit `APPLY=true CONFIRM=ATTACH_LICENSES` for a read-only rehearsal. The script enforces one CSV member, records the before-state, attaches missing licences, repeats the operation and requires a no-op, downloads both files to verify SHA-256, and checks that all non-LICENSE bundles are unchanged. It appends and flushes each phase to the report. Finally inspect the item's `/full` page to confirm the License bundle display. This canary checks attachment to an existing deposited item; a later normal export should also confirm real SWORD receipt handoff. Neither a successful local suite nor a read-only rehearsal proves REST write permissions.

Historical validation on 2026-09-16: the full non-browser Rails suite passed (279 tests, 1,082 assertions), followed by targeted recovery/concurrency checks. The production July canary was inspected read-only; no production attachment or bulk backfill occurred. Credentials were supplied privately through environment variables for the successful staging REST write described above, not saved in the repository. The remaining live validation gap is the SWORD-to-job pipeline.

### July backfill runbook

Dry-run the full CSV (no writes; reads authenticate if credentials are configured):

```sh
bundle exec rake dspace:licenses:backfill \
  CSV_PATH=/path/to/July2026_ETDs_master.csv \
  DSPACE_REST_API_URL=https://yorkspace.library.yorku.ca/server/api
```

Apply to one designated canary after configuring credentials in the application settings:

```sh
bundle exec rake dspace:licenses:backfill \
  CSV_PATH=/path/to/July2026_ETDs_master.csv \
  ITEM_UUID=00000000-0000-4000-8000-000000000000 \
  APPLY=true \
  CONFIRM=ATTACH_LICENSES \
  RESULTS_PATH=/path/to/dspace-license-canary.jsonl
```

Visually confirm the canary's **License bundle** and both downloaded file hashes. To apply the remaining CSV, repeat without `ITEM_UUID`; `LIMIT` can restrict a batch size. Every apply run requires both the confirmation phrase and an append-only JSONL results path. Reruns re-read current bundle state and skip complete records.

## Verified YorkSpace state

YorkSpace reports `DSpace 7.6.5` at its public [REST root](https://yorkspace.library.yorku.ca/server/api).

The supplied [known-good item](https://yorkspace.library.yorku.ca/items/c6831446-9fc0-4886-87cd-e34d09ddeacd/full) visibly separates one PDF under **Original bundle** from two plain-text files under **License bundle**. Its public [bundle response](https://yorkspace.library.yorku.ca/server/api/core/items/c6831446-9fc0-4886-87cd-e34d09ddeacd/bundles?size=100) contains distinct `SWORD`, `ORIGINAL`, `TEXT`, `THUMBNAIL`, and `LICENSE` bundles.

The two known-good bitstreams are:

| File | Bytes | DSpace MD5 | SHA-256 of downloaded bytes |
| --- | ---: | --- | --- |
| `license.txt` | 1,913 | `ad94d0cd27da622da832da123b629d9c` | `3887c1cf7f92224425250ff451b1f5e098c301710dbd59996a33f2280a01bd0c` |
| `YorkU_ETDlicense.txt` | 3,476 | `fff9673a29a2f5114b5773983cc2c94d` | `afdff8088f1ee77bcdb007ca632af8d21d35adb32364967560b46380d0d63f79` |

### July file audit

Input: `/Users/dndeli/Downloads/July2026_ETDs_master.csv`

- CSV SHA-256: `a5961b88a274e795387c3967c4b37ff6bd5695af4523f66ce45588d0a601b83a`
- 175 logical data rows
- 175 unique, syntactically valid UUIDs
- all 175 UUIDs resolved through the public YorkSpace bundle endpoint
- 174 records have no `LICENSE` bundle
- one record, [`d5a3c1a8-8694-45a9-bb9b-c10adb20ce87`](https://yorkspace.library.yorku.ca/items/d5a3c1a8-8694-45a9-bb9b-c10adb20ce87/full), already has exactly the two files and hashes above
- none of the other 174 records contains those canonical filenames or hashes in another bundle

The audit was read-only and performed on 2026-08-30.

## Why the current SWORD attempt behaves this way

The ETD exporter creates the item through SWORD and sends each file with `post_media!`; there is no bundle-selection argument in that path. See [`lib/etd/exporter.rb`](../../lib/etd/exporter.rb) and [`app/jobs/dspace_export_job.rb`](../../app/jobs/dspace_export_job.rb).

DSpace 7.6.5 documents the server-side result explicitly: when individual files are uploaded to the SWORD media resource, a copy is stored in the `SWORD` bundle and the `ORIGINAL` bundle. See the tagged [`swordv2-server.cfg`](https://github.com/DSpace/DSpace/blob/dspace-7.6.5/dspace/config/modules/swordv2-server.cfg#L100-L119).

## Supported REST workflow

The DSpace 7.6.5 REST contract provides both required operations:

- [`POST /api/core/items/{item-uuid}/bundles`](https://github.com/DSpace/RestContract/blob/dspace-7.6.5/items.md#bundles) creates a named bundle. It returns `201` when created and `400` if that bundle name already exists.
- [`POST /api/core/bundles/{bundle-uuid}/bitstreams`](https://github.com/DSpace/RestContract/blob/dspace-7.6.5/bundles.md#bitstreams) uploads one multipart file directly to that bundle. It returns the created bitstream and supports content length/checksum validation.

Both write operations require authentication and sufficient permissions. DSpace 7 authentication uses a CSRF token plus a login that returns a bearer JWT; see the tagged [authentication contract](https://github.com/DSpace/RestContract/blob/dspace-7.6.5/authentication.md#login).

The existing SWORD account may or may not have REST permission to add bundles and bitstreams to archived items. Confirm that with one non-production or designated canary item before a batch run.

## Safe batch design

The utility should default to dry-run and process item UUIDs from column A.

For each UUID:

1. GET the item and its bundles; stop if the item is absent or outside the intended ETD scope.
2. If there is one `LICENSE` bundle containing both approved filename-and-hash pairs, record `SKIP_COMPLETE`.
3. If there are multiple `LICENSE` bundles, duplicate filenames, or a matching filename with different bytes, record `REVIEW_REQUIRED` and make no change.
4. If the bundle is absent, create `LICENSE`, then re-read it to obtain its UUID.
5. Upload only missing approved files, one at a time.
6. Re-read the bundle and verify filename, byte count, and checksum after every upload.
7. Write a resumable result log containing item UUID, action, HTTP status, created bundle/bitstream UUIDs, and verified hashes. Never log credentials or bearer tokens.

Retries must re-read state before repeating a create or upload. A timeout after a successful server write could otherwise create duplicates.

Run one canary, visually confirm the full item page, then run the remaining records in small batches. The July backfill should skip the one already-complete item and target at most 174 records.

## Canonical payloads used by the implementation

The repository's existing [`public/documents/YorkU_ETDlicense.txt`](../../public/documents/YorkU_ETDlicense.txt) is not byte-identical to the live known-good file:

- local file: 3,456 bytes; SHA-256 `2a78463c49e16080e9bb79f44b2c2d85c45d7596d6c5e618aa0e55ff5bd170bb`
- live known-good file: 3,476 bytes; SHA-256 `afdff8088f1ee77bcdb007ca632af8d21d35adb32364967560b46380d0d63f79`

The differences include `licence`/`license` spelling and line endings. The implementation therefore does not use that public document. It versions exact copies from the supplied known-good YorkSpace item under `config/dspace/licenses/` and verifies them before every operation.

## Future deposits

Ordinary thesis/supplementary files remain in the SWORD deposit. For completed production exports, the application persists the item UUID from the successful SWORD receipt and enqueues the independent REST licence job. The licences are not added to the SWORD media-file array.
