# Walking a batch drain: a private copy of the database, a sink per effect, one row per comparison

Load when verification has to **run a batch consumer for real**: a cron action or queue worker that
selects rows by type and status (`WHERE req_type = ? AND status IN ('add', 'repeat')`) and acts on each
of them. Examples include a mail drain, a cancellation drain or a sync drain. Inserting fixture rows
and calling the drain looks like a unit-sized probe. It is not: the drain acts on **everything**
pending.

## 1. Count before you run: the drain takes every pending row

Before the first run, count the pending rows of every type the drain reads, on the database you are
about to point it at. On a shared development clone the count is often not zero, for example rows
copied from production or left by an earlier walk. Running the drain there would send real mail for
real carts, cancel real reservations, or call a real external API with the clone's credentials.

- Count non-zero → **do not run the drain on that database**, and never "clean up" another
  environment's pending rows to make room.
- Also read the outbound configuration the effects use: mail transport rows, API endpoints, credentials.
  These are read-only checks; never repoint a shared database's configuration.

## 2. A private copy of the database

- `mysqldump --single-transaction --routines --triggers <clone> | mysql <walk_db>` into a new schema on
  the same server. A few hundred MB copies in about a minute. Check that row counts of the tables you
  care about are equal in both schemas.
- Point the walk stack's environment at the copy only, through the worktree stack's env file, never the
  primary's. Enable the cron gate (`ENABLE_CRON_TASK`-style flag) there and nowhere else.
- In the copy, and only there: delete the copied pending rows, blank the outbound configuration rows,
  and mutate fixture records freely (a status, a cleared external id). Note each change in the
  verification doc.
- Drop the copy and stop the stack **after review**, not right after the walk. Fix cycles re-walk.

## 3. A sink for every outbound effect

- **Mail:** a `sendmail_path` (or the framework's equivalent) that appends each message to a capture
  file, so support and alert mails land there too. With the database's SMTP rows blanked, the framework
  falls back to that transport.
- **Missing extension or bus client** (a message-queue extension absent from the dev image, so the
  write fatals *after* the state change): prepend a walk-only stand-in class through the container's
  ini (`auto_prepend_file`). It records the send in a file. Keep it in an ignored scratch directory,
  never commit it, and remember that `php -r` does not honour the prepend while a script does.
- **External APIs:** pick fixtures that take the documented no-call branch (an unregistered record),
  confirm that branch in the code, and say so in the verification doc.

## 4. The drain runs unmodified, through its real entry

Drive it over its real route or CLI command. No scratch controller is needed once the effects are
sunk: the selection, claim, status writes and catch paths are exactly what you are verifying. Read
outcomes from the stored rows (status, error text, tries), the capture files and the drain's own log
output.

## 5. Compare variants one row per run; a batch shares process state

A drain loop runs every row in **one process**, so globals, locale, static caches and request
superglobals set by one row leak into the next. Two variants (the old key and the new key) placed in
one batch can differ for reasons unrelated to the variant. In the field, the two confirmation mails
differed in language, because the first row set a "current language" global that the method "restored"
by setting rather than unsetting it.

- Prove parity with **each variant alone in its own run**, comparing a header-normalised hash of the
  captured message (strip Date, Message-ID and MIME boundaries).
- Keep the mixed-batch run too. A difference that disappears when rows run alone is a real defect in
  the drain. Record it as its own finding, not as noise.

## 6. A discriminating row for every guard

For each condition the change adds, the walk needs a row that would **fail if the condition were
wrong**. A record that exits early cannot discriminate a condition that sits after the exit: an
already-cancelled reservation stops before an "is the e-mail due" check. Use a live record with the
condition false instead. Add a row for a malformed body (a JSON string, not an object) and confirm the
batch **continues** to the next row. A batch that dies leaves the row claimed and every later row
unprocessed.

## Related

- `LIVE_BEFORE_ORACLE.md`: two stacks over one database when you need a "before".
- `FALLBACK_HIDES_THE_BRANCH.md`: prove the branch ran, not a fallback that answers the same.
- `MUTATION_PASS_DISCIPLINE.md`: the walk row must be able to fail on the unfixed code.
- `../plan/references/HOST_LOCAL_VALUE_IN_A_QUEUED_ROW.md`: the change shape this walk was written for.
- `SHARED_DATABASE_WALK_WATERMARKS.md`: the narrow case (one request, one task by id) walked on the shared
  database itself, cleaned by whole-schema `AUTO_INCREMENT` watermarks.
