# A drain-once feed with a time floor — the floor must outlast the longest gap between polls

Load when a plan changes, or depends on, a **pull feed** that hands each row out once: an
external system polls an endpoint, the endpoint returns the rows still marked "not sent" and marks
them sent. The plan is most likely to need this when that endpoint also filters on a time floor
("rows created or modified since X"). Typical triggers: a report that late-evening records never
reach the consumer, a plan to widen or narrow the window, onboarding a tenant with a long
history.

## The shape

```sql
SELECT … FROM records
 WHERE sent = 0
   AND imported_from_consumer = 0
   AND (created >= :floor OR modified >= :floor);
-- then, before the response is written:
UPDATE records SET sent = 1, sent_at = NOW() WHERE id IN (:returned);
```

Two filters do two different jobs:

- **The marker** (`sent = 0`) is what makes delivery once-only.
- **The floor** exists so a consumer connected to an account with years of history is not handed
  all of it on the first poll. It is a backstop, not the selector.

The trap is a floor that **advances on its own**, such as "today 00:00" or "now minus N hours".
A row becomes eligible (created, or its marker reset) *after* the consumer's last poll before the
floor moves. At the next poll the row is below the floor. Its marker stays `0`, and nothing will
offer it again: it is stranded, silently and permanently. A consumer that polls every 30 minutes
loses whatever arrived after its last poll of the day, every day.

**The rule: the floor must look back at least as far as the longest gap between two polls you
intend to survive.** That includes the consumer's own outage or missed cron, not just its normal
interval. A floor that is too wide costs only a few extra rows scanned, because the marker
already excludes delivered rows. A floor that is too narrow loses data.

## What a wider floor does not recover

Write these into the plan's out-of-scope list. Do not let "the window is wider now" imply them.

1. **Changes that never reset the marker.** List the writers that set `sent = 0` by grepping the
   marker column. Do not assume "every update re-flags". In the field case, the model's update
   method reset the marker only when the payload carried the status column. A contact-data or
   check-in edit was never re-exported under any floor.
2. **A marker reset that does not bump the time column the floor compares.** A status writer that
   leaves `modified` alone re-flags a row whose time stamp may already be below the floor. For each
   reset site, check which time column it writes.
3. **Lost responses.** The rows are marked *before* the response reaches the consumer, so delivery
   is at most once. If the response fails in transit, the rows are already marked, and no floor
   brings them back. That is a delivery-guarantee problem (acknowledge on the next poll, or a
   cursor the consumer returns), and it needs its own IDEA.

## Plan checklist

- [ ] **Read the floor's parsing path end to end.**
  - An explicit per-account value (a pinned date) must still override the default. Keep it exactly
    as the config loader hands it over, and test that.
  - Find where that value is normalised. A pin the date parser cannot read can become the epoch
    (`1970-01-01`). That is a non-empty value, so it overrides the default and serves the whole
    history. Put it in the operator inventory.
- [ ] **Calendar days or a rolling window is the owner's decision.** Ask. "N days" read two ways is
  a real ambiguity ("since midnight three days ago" vs "the last 72 hours").
  - **Calendar:** take the date part of a relative-days expression, then append `00:00:00`. That is
    DST-safe, because a relative-days step keeps the wall-clock time and only the date is used.
  - **Either way, compute the floor on the clock that writes the compared columns** (see
    [`REVERSIBLE_EXPIRY_ON_TWO_PHASE_HOLDS.md`](REVERSIBLE_EXPIRY_ON_TWO_PHASE_HOLDS.md) § Two more
    things the design must settle: the cutoff is evaluated on the writing clock).
- [ ] **List every caller that can read the feed, not only the consumer it was built for.**
  - Widening the window widens what an over-permissive key can drain. If any API key can call the
    endpoint, any key can read three days of records and mark them sent, so the real consumer
    never receives them.
  - Check the endpoint's access gate: an IP whitelist that defaults to empty, a method list that is
    not enforced. Record a gap as a residual or a new IDEA.
- [ ] **Deploy sizing, read-only, per account.** The first poll after the widening delivers the
  backlog the old floor had stranded. Count it beforehand:
  - Group by status.
  - Write the "below the old floor" bound NULL-safe: `created < @old AND (modified IS NULL OR
    modified < @old)`. Never write it as `NOT (created >= @old OR modified >= @old)`, which is NULL
    for a NULL `modified` and drops rows the feed would return.
  - Use **literal dates**, not `CURDATE()`, unless the database session timezone has been checked
    against the clock that writes the columns.
  - With at-most-once delivery, a big first batch is also a big loss if that one response fails.
    Above a threshold, watch the first poll live. Afterwards, compare the rows stamped with that
    poll's `sent_at` with what the consumer shows.

## Testing the default

- **The expected value is the owner's number, written as a literal in the test.** It is never read
  from the constant the code uses. A test built from the constant compares the code with itself.
  It cannot catch a wrong constant, and on the base branch it errors on the missing constant
  instead of failing on the old value.
- **Compute the expected value before and after the call and accept either one**, so a run across
  midnight cannot flake.
- **Assert the exact string.** That rejects a rolling-window value (`… 14:23:11`) without a
  separate "is midnight" case.
  - Know what it cannot tell apart. "Today minus N calendar days" and "the date part of `now − N ×
    86400`" differ only in the hour around midnight in the N days after a DST switch.
  - Either accept that and record it, or inject a clock.
- **Execute the default.** A config loader on a framework controller can usually be reached
  without its constructor: build the instance without calling the constructor, set the registry
  entry, and invoke the method through reflection. Prefer that to a source-text pin (see
  [`../../work/references/EXECUTE_OVER_PIN.md`](../../work/references/EXECUTE_OVER_PIN.md)).
- **When the test changes a process-wide registry entry, restore it to absent if it was absent**
  (see [`../../work/references/RESTORE_ABSENT_GLOBALS_AS_ABSENT.md`](../../work/references/RESTORE_ABSENT_GLOBALS_AS_ABSENT.md)).

## Anti-patterns

- ❌ "Today 00:00" (or any floor that moves on its own) on a drain-once feed polled on someone else's
  schedule.
- ❌ Claiming the wider floor re-exports "every change" without listing the marker-reset writers.
- ❌ Treating the floor as a delivery guarantee. It cannot recover a response lost after the rows
  were marked.
- ❌ Scoping the new default to the expected consumer by name when the actual problem is that
  other callers can reach the endpoint. Fix the access gate, or record the gap.
- ❌ A sizing query with `NOT (a OR b)` over a nullable column, or `CURDATE()` against wall-clock
  strings written by another clock.
- ❌ A test whose expected value reads the constant under test.
