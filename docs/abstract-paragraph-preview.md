# Abstract paragraph preview

The student details form and staff thesis form share a paragraph-spacing preview.
It updates as the abstract is edited, without rewriting the textarea or changing
the export pipeline. A blank line separates paragraphs; a single newline is
displayed as a space. CRLF and CR line endings are normalized only for preview.
Markup is displayed as literal text, not executed or rendered as HTML.

The preview is deliberately not a complete YorkSpace/Markdown renderer. Lists,
math, HTML, Markdown hard breaks, and other formatting are outside its scope.
Without JavaScript, the textarea, formatting guidance, and normal save flow remain
available; the preview is hidden.

## Why paragraph boundaries require review

The supplied ETD examples retain single newlines. However,
[ETD 5570](https://etd.library.yorku.ca/students/5330/theses/5570) also contains
newlines inside sentences. Converting every newline into a paragraph would split
sentences incorrectly. Students or staff should compare the text with the PDF,
remove copied line wraps, and add blank lines at the intended paragraph boundaries.

On 2026-08-28, the public metadata for the
[matching YorkSpace item for ETD 5690](https://yorkspace.library.yorku.ca/items/966c5a94-5d89-47ee-9479-f770a90dde59)
contained two newline characters before its second paragraph, and its item page
rendered two paragraphs. ETD's textarea had shown only one newline at that point
when inspected on 2026-08-27. YorkSpace's deployed JavaScript uses Markdown-it for
Markdown rendering. This difference does not establish who changed the metadata
or when it changed.

Existing ETD and YorkSpace records are not automatically corrected. This change
does not add HTML to export metadata, alter published records, or make a deposit.

## Verification

Run in the existing Docker web container with `RAILS_ENV=test` and
`DATABASE_URL=mysql2://root:mypasswd@db/etd_test`:

- `bundle exec rails assets:precompile` (refresh precompiled JavaScript first)
- `bundle exec rails test test/jobs/dspace_export_job_test.rb`
- `bundle exec rails test test/system/abstract_preview_test.rb`

The tests cover student/staff preview behavior, manual corrections, literal
markup, empty input, narrow-screen layout, normal browser CRLF submission, and
preservation of abstract text through serialized export metadata.
