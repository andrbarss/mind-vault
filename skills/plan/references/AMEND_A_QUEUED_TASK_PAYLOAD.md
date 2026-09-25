# Amending a queued task's stored payload — compare-and-set, and refuse what the task will never read

Load when a plan writes into the stored payload of a task that is **already queued**: a deferred
registration job, a scheduled export, a retryable outbound call whose arguments were frozen into a
JSON column at enqueue time. Typical trigger: a later request changes a value the task carries, and
the task must pick up the new value when it finally runs. The write is small, but the task table is
shared with a worker that also writes the payload (idempotency ledger, retry state), and the task
has a lifecycle the new writer does not own.

## 1. Compare-and-set on the state *and* the whole payload

Read the task, transform the payload in memory, then write it back with one conditional statement:

```sql
UPDATE tasks SET payload = :new, modified_at = :now
 WHERE id = :id
   AND status IN ('queued', 'retry')   -- never a task a worker has claimed
   AND payload = :old                  -- byte-identical to what was read
```

- **The status guard** keeps the write away from a task a worker is running. The worker read the
  payload when it claimed the task, so a write after that point is lost silently.
- **The payload guard is what protects the worker's own writes.** Workers commonly record progress
  in the same payload (an idempotency ledger: "the remote record was already created, id X"). A plain
  read-modify-write that loses a race writes the *old* payload back. It **erases the ledger**, and the
  next retry creates the remote record a second time. Comparing the whole payload turns that race
  into a no-op the caller can log. Guarding a version column instead is equivalent only when *every*
  writer bumps it.
- **"Rows changed = 1" is the success signal.** Zero means missing, claimed, or changed, and all
  three are logged, never forced (`COMPARE_AND_SET_GUARD_SCOPE.md` § 3).

## 2. Refuse a payload the task will never read your key from

A task's payload is read by *stages*, and a retry does not re-run every stage. A worker that
recorded "remote record created" in its ledger **adopts** that record on retry and skips the step
that consumed the options you are about to amend. A marker written into that payload is accepted,
returns success, and is never read: a silent loss that looks delivered.

- Before writing, decode the payload and check the ledger fields that make the worker skip your
  consumer. If they are set, **refuse and log**. If the value still matters, send it by the path that
  applies to an already-created record.
- Refuse also when the payload is not the shape you expect (no options object). Never create the
  structure the producer did not.
- Keep the transform (decode → checks → set the key → encode) a **pure static function**, and
  execute it in tests: the shape refusals, the ledger refusal, an empty-ledger acceptance, and "every
  other key byte-for-byte unchanged". Pin the SQL of the conditional write as text if the table
  cannot be reached in the suite. Mutation-check the pin (drop the status clause; the test must fail).

## 3. List every other writer of the payload — the residual race is theirs

Grep for every read-modify-write of the same column, such as the step that moves the task to "ready"
with payment data, or the worker's ledger write. Each is a writer your compare-and-set cannot protect
against if **it** is not conditional: when it read before you wrote and writes after, it restores the
old payload and drops your key. Decide per writer: make it conditional too, or record the window. It
usually needs two concurrent requests on one record. Name it in the plan and the archive, not "races
are handled".

## 4. A second source of a key changes what the key means

When the worker branches on the key's **presence** ("present = the caller collected an answer"),
your marker adds a second source for the same signal. Update the consumer's comment and every doc
that states the old meaning (the solution doc, the contract). The next change to the consumer
otherwise breaks the new writer's contract without any test failing.

## Checklist for the plan

1. The task's lifecycle states: which ones may be amended (not claimed, not done).
2. Every writer of the payload, and which of them are conditional.
3. The ledger / adopt fields that make your key unread: refuse on them.
4. The conditional `UPDATE` (status + whole payload), `rows changed == 1`, misses logged.
5. The transform as a pure, executed function; the SQL pinned and mutation-checked.
6. Every consumer and doc that reads the key's presence, updated for the second source.

## Related

- `COMPARE_AND_SET_GUARD_SCOPE.md`: guard every input the computation read; rows changed vs matched.
- `LOCAL_FLAG_INTO_AN_EXTERNAL_RECORD.md`: the value being carried is often a local flag headed for
  an external record.
- `CLAIM_BEFORE_SIDE_EFFECTS_NEEDS_A_WAY_BACK.md`: the worker side of the same ledger.
