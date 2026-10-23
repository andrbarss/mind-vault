# Capping a queue that retries forever: the default, the busy window, the newest push, the clean-up

**Load when** a plan puts a limit on a task queue whose producer used to give tasks an "effectively
infinite" try count (`PHP_INT_MAX - 1`, `Integer.MAX_VALUE`, `retries: -1`), or adds de-duplication
of identical pushes to such a queue, or writes the one-off clean-up of the tasks already queued
under the old default. This is the **producer** side;
[`ENDPOINT_BEHIND_A_RETRYING_QUEUE.md`](ENDPOINT_BEHIND_A_RETRYING_QUEUE.md) covers the endpoint
the worker calls.

**Field case.** An async-HTTP queue retried every non-200 every ~5 s with no limit. A burst of
edits to one reservation pushed the same full-state PMS update twice, twice over, and the PMS
answered 500 to both. Four jobs then looped about 51,000 times a day for seven weeks, and each
attempt wrote the guest's name and the PMS key into an access log. Nothing alerted: the worker's
give-up branch needed the try count to run out.

## 1. A finite default, and the producers that must not take it

A default cap (10 tries here) is the easy part. The trap is the producers whose target answers 5xx
**while it is merely busy**, not broken:

- A trigger whose target takes a lock and answers "500, will be repeated" while another run holds
  it relies on the endless retry to wait the lock out. Under a 10-try default it gives up after
  ~50 s while the target is still busy, and the run is lost silently.
- **Enumerate the producers by target, not by caller.** For each target, read its busy path: what
  it answers while locked, and how long the lock can be held (its stale-lock timeout is the
  upper bound). Grep the target's action for the busy reply, then every producer that queues it.
- Give those producers an **explicit limit sized to the window**: `lock timeout / retry spacing`,
  rounded up (600 s / 5 s → 120; 3600 s / 5 s → 720). Name the constant after the window
  (`MAX_TRIES_LOCKED_600S`), not after the caller, so the next trigger reuses it.
- Producers that already pass a short explicit limit over a busy target are a pre-existing
  residual. List them in the plan's out-of-scope section rather than silently changing them.
- Write the rule where the next trigger's author will read it, next to the "add a trigger" recipe:
  *a target that answers 5xx while busy needs a limit covering its lock window; the default gives
  up while it is still busy.*
- Pin the classification of **every** producer call site in a test (target → limit → flag), so a
  new site has to be classified to pass.

## 2. De-duplicating full-state pushes: keep the newest, skip only the untried

"Don't queue a URL that is already waiting" is wrong for full-state writes:

- **A, B, A.** The third push is identical to a waiting one, but skipping it leaves B as the last
  state the target receives. The target ends on a state the source no longer has.
- **The rule:** skip a push only when the identical push is the **newest** waiting push to the same
  target host *and* it has **never been tried**. A, A queues one; A, B, A queues three.
  - "Newest" keeps the last write last.
  - "Never tried" stops a retrying (failing) push from absorbing new ones. A push that has failed
    once may fail for a reason the new push does not share.
- **Opt in per call site.** Only pushes whose URL carries the complete state (an idempotent
  full-record update) qualify. Partial updates, increments and triggers keep every push.
- **Compare byte for byte, in application code.** A case-insensitive column collation makes
  `WHERE url = ?` match a URL that differs only in case, and a case-only difference in a query
  string can be data.
- Key the "newest push" per **origin** (scheme + host + port, lower-cased), and never de-dup an
  empty or host-less URL.

Implementing it per store:

- **A key-value queue (Redis-shaped):** keep a per-origin marker `<hash(url)>:<job id>` of the
  newest flagged push. Check and move it in one optimistic transaction:
  `WATCH marker` → read it → confirm the job is still in the pool and untried → `UNWATCH` and skip,
  or `MULTI` (add the job, `SET marker … EX <ttl>`) → `EXEC`.
  - An aborted `EXEC` means another push moved the marker: re-evaluate once, then add **unwatched
    and still mark**. A lost push is worse than a duplicate.
  - Release the `WATCH` on every exception; a `WATCH` left on a shared connection conditions every
    later transaction of that request.
  - Only flagged pushes move the marker, so "newest" means the newest *flagged* push. Say so.
  - The marker is a hint, verified against the pool on every read, so a stale one costs a lookup.
- **A table queue:** select the newest waiting row to the origin with the drain's **own** waiting
  predicate (status and `tries < max_tries`), `ORDER BY id DESC LIMIT 1`, then compare in code.
  Using the drain's predicate matters: a row stuck in a retry status with no tries left is not
  waiting, and must not block a push.
  - Without a unique key, two truly concurrent identical inserts can both pass. Write it down as a
    residual, or add the key.
- **Logging a skip:** log the URL's hash, never the URL. A PMS URL carries the key and personal
  data.

## 3. The clean-up of tasks queued under the old default

The new default only applies to new tasks. The old ones still carry the infinite count and need a
one-off operator park. The selection is the dangerous part:

- **"Failed N or more times" is not enough.** After the deploy, the queue also holds tasks with the
  new, legitimate large limits (§ 1). A lock-guarded trigger 15 tries into its 120-try window has
  "failed 10+ times" and is doing exactly what it should.
- **Select by the old default's signature, above every limit the code legitimately passes:**
  `max_tries > <largest legitimate limit>` *and* attempts ≥ N *and* the task type the change
  covers. Grep for every explicit limit and take the maximum; a test of the selection that
  includes a fixture at each legitimate limit is cheap.
- **Take, then move.** Remove the job from the pool first (`ZREM`, or a status-guarded `UPDATE …
  WHERE status IN (waiting)`), and move it to the error store only when the take succeeded. A
  worker that popped it meanwhile keeps it.
- Never touch jobs a worker holds; report them and re-run later.
- Dry run by default. Show counts per target host and method, never the URLs. Re-run the dry run
  minutes later and again an hour later; tasks queued before the deploy can still arrive.
- Report records that are in no queue structure (job data with no pool entry) separately. They are
  pre-existing orphans, not work for the park.

## 4. The give-up path the cap makes reachable

A finite limit turns on a branch that never ran: the drain's give-up log line and alert mail.

- Read what it prints before shipping. A branch that never ran was never reviewed: here it mailed
  the full task URL, key included.
- Print a label (`#id type host method`) instead of the URL, with the method sanitised to a short
  identifier pattern.
- Check every sibling give-up branch (one per task type is common). Fix them or hand them to a
  follow-up by name.
- **If the production consumer is an external worker** that only logs a give-up on its own host,
  nothing reports it. Record "no give-up report" as a residual and an owner decision.

## 5. Plan checklist

- [ ] Every producer is classified by target: default, window-sized limit, or existing explicit
      limit (out of scope), and the classification is pinned in a test.
- [ ] Busy targets are found by reading their busy reply and lock timeout, not by name.
- [ ] De-dup is opt-in per call site, for full-state pushes only, and skips only the newest untried
      identical push (A, B, A → 3), compared byte for byte per origin.
- [ ] The key-value path is one optimistic transaction, with the abort retried once and then an
      unwatched, still-marked add, and the watch released on exceptions.
- [ ] The table path uses the drain's own waiting predicate.
- [ ] The park selects above every legitimate limit, takes before it moves, skips held jobs, dry
      runs by default and is re-run after the deploy.
- [ ] The newly reachable give-up branch prints no URL, and its siblings are listed.

## Related

- [`ENDPOINT_BEHIND_A_RETRYING_QUEUE.md`](ENDPOINT_BEHIND_A_RETRYING_QUEUE.md): the status code as the
  retry instruction, and the ordering residual of a retried older task.
- [`FAN_OUT_THROUGH_A_SHARED_SERIAL_QUEUE.md`](FAN_OUT_THROUGH_A_SHARED_SERIAL_QUEUE.md): one bad target
  on a shared drain.
- [`AMEND_A_QUEUED_TASK_PAYLOAD.md`](AMEND_A_QUEUED_TASK_PAYLOAD.md): changing what a pending task will
  send, with a byte-identical guard.
- [`../../work/references/EXECUTE_OVER_PIN.md`](../../work/references/EXECUTE_OVER_PIN.md) § the hand-written
  fake: settle the transaction semantics the de-dup relies on against the real server.
