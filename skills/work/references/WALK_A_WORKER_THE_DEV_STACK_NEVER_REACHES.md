# Walking a background worker the dev stack never reaches

Load when a verification step says "walk the worker on the dev stack" and the worker is fed by a producer
with a configuration gate (an engine type, a feature flag, a provider switch) that the dev stack does not
satisfy, or sits behind an action the dev env disables. The plan's walk reads fine and cannot run; the
usual discovery is at `/work`, after the code is written.

## 1. Read both gates before designing the walk

- **The producer's gate** — what records the task. A deferred-registration task was recorded only when the
  engine type was neither "local" nor the one provider that registers synchronously, *and* sync was
  enabled; the dev env ran engine type 0, so the request path inserted the record and never queued the
  task. The plan's chain (request → save → pay → worker) stopped one step before the worker on every
  run, with nothing failing.
- **The consumer's gate** — what lets the worker action run. The cron controller answered `Disabled`
  under the dev env's `ENABLE_CRON_TASK=false`. A worktree stack with its own env file flips it without
  touching the shared stack.
- **The branch the real collaborator takes** — with no external system configured, the sync client
  answered "no external registration required" and the new step was skipped by design, so even a reached
  worker would have proved only the skip.

Write the three answers into the plan's verification section. "The dev stack has no provider, so the
worker takes the TRUE branch" is a claim about the consumer; it says nothing about whether the task is
ever recorded.

## 2. Hand-insert the task row

The producer's gate is the request path's business; the worker's contract is the task row. Insert the
row the producer would have written (type, url, status, tries, max tries, the payload the worker decodes
— including the fields a side step parses, such as the dates a temp-row register turns into `DateTime`)
with a tag in a free column (`createby`) that the cleanup can target. For the retry path, write the
ledger fields into the payload and set `tries` as a retry would. Then call the worker action by id. One
row per variant; the ids come back from `LAST_INSERT_ID()` read with the client's no-header flag
(`mysql -N`), never parsed from a filtered listing — a warning line with an unexpected spelling turned a
parsed id into garbage and two variants ran against nothing.

## 3. Stand in for the outbound client with a prepend — when the class is autoloaded

A missing extension's classes can be pre-declared in a prepend file (the sibling case in
[`WALK_A_BATCH_DRAIN_ON_A_PRIVATE_COPY.md`](WALK_A_BATCH_DRAIN_ON_A_PRIVATE_COPY.md)). The same mechanism
stands in for an **application class** — the outbound sync client — under one condition: **nothing on the
path `require_once`s its file.** A class that is already declared is never autoloaded, so a pre-declared
`SyncClient` wins silently; a `require_once` of the real file anywhere on the path fatals with a
redeclare. Grep for `require.*<Class>` first (a comment mentioning the file is not a load).

The stand-in answers like a configured provider — the create call returns an id, the per-child call
returns an id per row with one row refused on purpose (to show the refusal outcome and the pause after
it), `__call` returns `true` for every other method the tail invokes — and reads a **mode file** to flip a
branch (`createReservation → TRUE`) between variants without editing the stub. Every call is appended to
a hits file with the arguments that matter (the parent's external id as the client saw it); that file is
the walk's evidence, next to the application's own log lines and the rows after.

Keep the ini and the stub in the worktree only (its own php-fpm reads `public/.user.ini`), in ignored
paths, and remove the ini when done. Commit the stub and the scripts into the archive's walk directory so
the run is reproducible — with paths derived from the script's location, not from a session's temp dir.

## 4. Variants worth running

- The happy path: several eligible rows, one refused, pauses visible as timestamps, the parent's
  write-backs, the temp row reaped, the task done.
- The retry (adopt) path: a task whose payload already carries the ledger; expect **no** create call and
  only the rows still without an id re-sent.
- The skip branch: the stand-in in its `TRUE` mode with an eligible row still present; expect no
  per-child call and no per-child log line — a discriminating negative, because the row *would* have been
  sent.

## 5. Cleanup on the shared clone

Rows by the fixture's own fingerprint (the tag column, a sentinel name, an id prefix on the external ids),
never by the id range of one run (`BETWEEN 900123 AND 900127` leaves the next run's rows). The parent row's
touched columns restored from the backup the fixture script printed before the walk, and a residual
query after. Watch for a `rm -rf` of a log directory the repository tracks placeholders in — `git
checkout -- <dir>` restores them.

**Last Updated**: 2026-10-09 (captured from a deferred-registration worker walk; the plan's step was
unreachable on the dev stack for both gate reasons in § 1).
