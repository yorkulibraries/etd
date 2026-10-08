# Snapshot document type fix

## Problem and scope

A staff thesis page can return HTTP 500 after submission includes modification request files. Document accepts that usage, but ThesisSubmissionDocument does not return a label, and the snapshot view calls humanize on nil.

The fix adds the missing label and displays Unknown for unexpected stored types. End-to-end verification also found that the snapshot uploader moved original uploaded files into its cache. Removing that override makes snapshots copy existing files; moving the disposable cached copy into snapshot storage remains enabled. No migration is required. Upload workflow and export selection are unchanged.

## End-to-end verification

The regression is test/system/submission_versions_test.rb. It must be written and reproduce the display failure before changing application code.

Use a separate Rails test database with MySQL, the installed bundle, and Chrome/Chromedriver. The database URL must contain test because the test helper deliberately truncates its test database. Never run this test against QA or production data.

Run:

```sh
RAILS_ENV=test DB_ADAPTER=mysql2 bundle exec rails test test/system/submission_versions_test.rb
```

Evidence is written to tmp/snapshot-document-types-evidence. The test checks every current usage, real student submission, staff return with notifications disabled, draft replacement without a new snapshot, a second submission, source files surviving snapshot creation, authenticated downloads and SHA256 comparisons, and an unexpected stored type label. The replacement PDF contains different visible text.

## QA deployment and verification

Merge the reviewed fix through staging using the normal repository process. Deploy the resulting commit to the QA application and restart its Rails workers using the site's established method. Confirm the running commit matches the deployment.

Open /students/4314/theses/4473 as staff. Confirm Submitted Versions renders and modification request attachments have the correct label. Download the existing original and revised primary snapshots and compare their contents. Check the QA log for this request and confirm HTTP 200 without a new template error.

Do not delete snapshots, run the backfill task, resubmit the thesis merely to repair display, or run DSpace export as part of this fix. Existing snapshot count and preserved files should remain unchanged by deployment. Also check the current draft downloads. Earlier snapshots may have consumed those draft source files; code deployment prevents future occurrences but does not restore previously moved files. Any recovery must copy the matching preserved file back only if the current source is missing, without overwriting a newer revision.

Rollback: deploy the previous application commit and restart its Rails workers. There is no schema change to reverse; rolling back also restores the reported display bug for records with modification request snapshots.

## Current status

Local verification is complete. The fixed end-to-end workflow passed with 69 assertions and the existing controller coverage passed with 57 runs and 219 assertions. No Git push or QA deployment has occurred yet. The saved JSON evidence records matching SHA256 hashes for version 1 and version 2 downloads. An earlier rerun encountered a transient MySQL table-definition retry before any assertions; the final rerun passed cleanly.
