# Replacing a child set under row locks — a non-transactional parent locks nothing, and an empty InnoDB range deadlocks instead of queueing

Load when a plan serialises a **delete + reinsert (or read-modify-write) of a parent's child set**
with `SELECT … FOR UPDATE` / `lockForUpdate()` / Django `select_for_update()` — especially when the
**parent row is meant to be the mutex**, or the set **can be empty** (every first save). Also load
when reviewing any plan, docblock or contract that says a lock "serialises concurrent saves".

Sibling: [`UNIQUE_KEY_TWO_LAYER_WRITER.md`](UNIQUE_KEY_TWO_LAYER_WRITER.md) already warns that
`FOR UPDATE` on a *non-existent unique value* takes a gap lock that deadlocks inserts. This file is
the set-replace shape of the same mechanism, plus the parent-lock half and the design that works.

## Two beliefs that fail on real schemas

1. **"Lock the parent row and the writers queue."** Only if the parent table has row locks. A
   MyISAM parent (common on legacy schemas, and engines can differ per table and even per tenant)
   answers `FOR UPDATE` as a **plain read**: the second session returns immediately. A sibling
   writer that already takes this lock is not evidence that it works.
2. **"`FOR UPDATE` on an empty child range locks nothing" — or "…serialises the first save".** Under
   REPEATABLE READ (MySQL's default) with an index on the parent column, the locking read takes a
   **gap / next-key lock** even when no row matches. Gap locks are **compatible with each other**:
   both sessions acquire the gap, each `INSERT` then needs an insert-intention lock that conflicts
   with the *other* session's gap lock, and InnoDB kills one with **1213**. With existing rows the
   second session waits on record locks and becomes the deadlock victim when the first inserts. On
   a **sparse index, two different parents can share one gap**, so saves of unrelated parents
   deadlock too. Under READ COMMITTED the empty-range read takes no gap lock at all: both writers
   insert, and the collision surfaces as a **duplicate key** (1062) — or silent duplicates without a
   unique key.

Neither shows up in a single-session test suite.

## Measure it — the probe that tells the truth

Field measurements (MySQL 8.0, REPEATABLE READ, two sessions, session 1 holding its transaction
for 3 s, timed on the database host):

| Probe | Session 2 |
| --- | --- |
| MyISAM parent, `FOR UPDATE` on the same row in both sessions | returned in **11 ms** — no lock |
| InnoDB child table, empty range: S1 lock + insert, S2 lock + delete | waited until S1 committed |
| S1 lock only (no insert), S2 lock + insert | S2's insert waited on S1's gap |
| S1 on parent A's empty range, S2 on parent B's (sparse index) | S2 still waited — shared gap |
| **Both sessions lock, then insert** (the writer's real shape) | S2's lock returned in 3 ms; the inserts then **deadlocked (1213)** |

Rules for the probe:

- **Both sessions run the writer's full sequence** — lock, delete, insert. A one-inserter probe
  (row 3) shows a wait and reads as "serialised"; only the two-inserter probe (last row) shows the
  real outcome. The first author and the plan both got this wrong from the one-inserter shape; the
  architect's rerun with two inserters caught it.
- **Time it where the client can't hide a wait.** A wrapper such as `docker exec … mysql` from the
  host can cost seconds per call, so every probe "waits" about the same. Measure the overhead with a
  `SELECT 1` first, and run the timed sessions on the database host or inside its container.
- **Check the parent's engine** (`information_schema.TABLES.ENGINE`) for every tenant class the
  code will run on, not only the dev database.
- **Record** engine, isolation level, each probe and its milliseconds in the plan's verification
  section, so review can check the claim against numbers rather than prose.

## The design that works — serialise by retry, translate what survives

- **Retry the whole replace on a concurrency error.** Laravel: `DB::transaction($callback,
  $attempts)` re-runs the callback when `DetectsConcurrencyErrors` matches (deadlock, lock-wait
  timeout) — but only at transaction level 1; nested inside a caller's transaction it rethrows at
  once. Django: there is no built-in retry; loop over `transaction.atomic()` and retry on the
  driver's deadlock error. The retried unit must include every re-read and re-check, not just the
  insert. The resulting semantics are **last commit wins** — confirm that is what the set means
  (for a form that sends the whole set, it is).
- **Re-check invariants inside each attempt** (targets still exist, still belong). With an unlocked
  parent the re-check only *narrows* the race, so readers must tolerate the leftover (orphans hidden,
  dropped by the next save) — say so in the contract.
- **Translate after the retries, narrowly.** A residual deadlock / lock-wait, and a duplicate-key
  error on a table where de-duplicated input can only collide with a concurrent writer, become a
  user-facing conflict message ("another save conflicted with this one — reload and save again").
  Everything else stays loud. Keep the message neutral: the conflicting save may be of a different
  parent.
- **Never translate inside a caller's transaction.** The database has rolled back the whole outer
  transaction; reporting "the record saved, only the set didn't" is false. Check the transaction
  level and rethrow.
- **Make one attempt a seam** (a protected method called inside the retried callback) so tests can
  fail an attempt exactly as the database does: retried then succeeds (attempt count 2, one copy of
  the set); retries exhausted (the message, never driver text, never a 500 on a create path without
  an outer catch); a non-concurrency error (not retried, not disguised); a caller's transaction
  (rethrown raw).

## Review check

For any "lock X to serialise Y" line in a plan or docblock, ask four questions: what engine is X on
every tenant class; what isolation level; can the locked range be empty; do *both* writers insert?
If the answers are not measured, require the two-inserter probe or the retry design. An existing
writer with the same pattern is a recorded exposure, not an automatic scope widening.

## Anti-patterns

- ❌ Copying a sibling writer's parent-row `FOR UPDATE` onto a new writer without checking the
  parent's engine.
- ❌ A lock probe in which only one session inserts.
- ❌ Timing a lock probe through a client wrapper with multi-second overhead.
- ❌ Writing "serialised per parent" in a contract or docblock when the mechanism is retry.
- ❌ Translating every database exception into the friendly message — it hides real bugs.
- ❌ Translating inside an outer transaction.
