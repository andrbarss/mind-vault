# Claim before side effects needs a way back — and the way back must reach the replay

Load when a plan closes a race by **moving a state transition ahead of the work it gates**: an
atomic claim (`UPDATE … SET state = done WHERE id = ? AND state < done`, continue only when one
row changed) placed before the order row, the generated code, the cloned sibling records, the
outbound call. The claim is the right tool — a read-then-write guard several statements long lets
two workers both pass it — but it silently trades one failure window for another, and the fix for
the new window has three parts, each of which was missed once on the way to a working one.

## What the move changes

Legacy order: *side effect A → write state → side effects B, C*. A failure in A leaves the state
untouched, so the caller's retry (a payment processor's repeated callback, a queue redelivery)
simply runs again — **the retry is the recovery mechanism**, and it works because every entry
point gates on "state still below done".

Claim-first order: *claim state → A → B → C*. The race is closed and a replay can no longer
duplicate A. But a failure in A now leaves the record **claimed with none of its effects**: state
says done, no order row, no code, no siblings — and the same gate that made the retry safe now
makes it a no-op. The retry cannot repair what it is not allowed to enter. Compare the two
orderings honestly in the plan: *better* (race, duplicate A), *same* (a crash after the state
write was always unrecoverable), *worse* (the unrecoverable window now includes A).

**Audit the gated call's adapters first.** The move is only available when nothing the outbound
call dispatches to reads the column the claim changes. An adapter that re-reads the table to decide
what to send (`state != done AND external_id = ?` — "cancel the whole external record, or re-send
the siblings to keep") sees the claimed row as already gone and does the wrong thing on every call,
race or not. Grep every adapter before choosing; when one reads it, the design is
[`RECHECK_OUTBOUND_GUARDED_WRITE.md`](RECHECK_OUTBOUND_GUARDED_WRITE.md) — today's order with a
re-check before the call and a guarded write after it.

## The way back, in three parts

1. **Release the claim when the first gated effect fails — guarded to the bare claim.** Restore
   the previous state only `WHERE id = ? AND state = done AND <first artefact> IS NULL`: a release
   that fires after artefacts exist would un-finish a finished record. Read the previous state
   **before** the claim and pass it in; "the claim does not touch the in-memory object, so
   `getState()` still answers the old value" is true until somebody tidies the claim method, and
   no source pin notices.
2. **The release must never throw.** It runs inside the `catch` of the failed effect, usually on
   the *same connection* — and the likeliest reasons for the failure (a lost connection, a lock
   wait, a deadlock) break the release too. An exception from the release **replaces** the
   original one (PHP and Python do not chain it for you in a bare `catch`/`except` body) and
   leaves the claim in place: exactly the stranded state, now with a misleading error. Wrap it,
   log it, return false, rethrow the original.
3. **Free every outer idempotency lock on the way out.** Callbacks are commonly wrapped in a
   per-request-id lock (`SET key NX EX ttl`; a repeat with the same id is answered "already
   processed — success"). An exception that escapes the handler leaves that lock held, so the
   caller's repeat — *same id* — is acknowledged without running. The claim was released and
   nothing will ever retake it. Catch around the gated work, release the lock exactly as the
   handler's own refusal branches do, rethrow. Check what "the call fails" means on the wire while
   you are there: an error controller that leaves the status at 200 still tells some callers
   "delivered".

## Walk the heal, with the same key

Source pins can show the three parts exist; only a live run shows the repeat heals. Inject the
failure (a `BEFORE INSERT` trigger that `SIGNAL`s for one key is enough — and assert it is armed),
send the call, read the rows (claim released, no artefacts), remove the fault, send the repeat
**with the same idempotency key**, read the rows again (one artefact of each kind), then send a
third (short-circuited). A repeat with a fresh key proves nothing about part 3.

## The claim must not travel through a stamping writer

The obvious way to write the claim is the model's ordinary update method — the one every other
writer uses. That method often does more than write: it stamps a *re-sync marker* (an
`ext_synchronized = 0`, an `updated = 1`, an outbox row, a `modified_at` a change feed selects on)
whenever the state column is in the payload. A change-feed consumer — a pull endpoint, a sync cron,
a webhook fan-out — that drains rows by that marker can then run **between the claim and the
completion**: it exports the record as *done* with the amounts not yet written, and marks the row
consumed, so the completion's real values are never picked up. The field case was a pull feed that
selected `synchronized = 0`, emitted a payment block whenever `status > 1`, and set the flag back;
a stamped claim would have exported "paid, amount 0" and the feed would never have looked again.

The rule: **the claim goes through the raw writer and carries the state column only** (plus the
audit stamps every write carries — modified-at, modified-by); the amounts and the re-sync markers
are written by the *completion*, after the gated call answered. Two further reasons line up behind
the same split:

- **Readers that re-derive the amount.** An import loop that computes `delta = external − local`
  once the state is *done* sees `local` unchanged during the window and computes 0 — the window
  that the legacy order already had, not a new one.
- **The bare claim is recognisable without a schema change.** A row with the state moved and the
  amount columns exactly as read *is* the claim; the release guards on that (`state = done AND
  amount = <read> AND amount_date <=> <read>`), a completed record never matches it, and a claim
  stranded by a kill from outside is **refused loudly** by the caller's repeat (`amount != expected`)
  instead of being acknowledged "already done" by the idempotent arm. A full-payload claim loses all
  three: the repeat of a stranded claim looks identical to a finished one.

Two consequences to write into the plan and the API text, because they are what a reader of the
old code does not expect:

- **A concurrent duplicate is refused, not idempotent.** The second caller that arrives while the
  first is still inside the gated call re-reads the bare claim (`done`, amount 0) and the legacy
  decision refuses it; a duplicate that arrives after the completion is idempotent. One effect
  either way, but the duplicate's answer differs by timing — say so where the callback's contract
  is documented, and log the refusal.
- **The idempotent arm cannot tell a bare claim from a finished record when the amount already
  matches** (amount 0 calls, an amount pre-set by another writer): keep the legacy comparison when
  tightening it would refuse the repeat of every legacy record that lacks the date, and name the
  residual.

The hook that re-selects "the row just written" with the caller's WHERE
([`COMPARE_AND_SET_GUARD_SCOPE.md`](COMPARE_AND_SET_GUARD_SCOPE.md) § 2) is then never reached by
either write: fire the model's post-update event once, by key, after the completion, with the
payload the legacy single write carried.

## The way back has a third leg: the fatal nobody catches

Part 2 above releases inside the `catch` of the failed effect. A **fatal error** inside the gated
call — a time limit, memory exhaustion, an uncaught engine error — runs no catch and leaves the
claim exactly as a kill from outside would, and on a slow outbound call that is a recurring cause,
not a rare one. Register the claim as *in flight* immediately before the call (key → the model,
the row as read), settle it on both exits (after the call and in the catch), and register a
**shutdown function** — once per process — that releases every claim still in flight when the
process ends, through the same never-throwing release with "the process ended inside the call" as
the recorded cause. The shutdown function cannot throw either (it runs after the fatal), and it runs
on the connection the fatal left open. A kill from outside (SIGKILL, an OOM killer) runs no shutdown
function: that is the residual — write the fingerprint (`state = done AND amount = 0 AND amount_date
IS NULL AND modified_at < now − N AND no artefact row`) and the repair (the release statement, then
let the caller's repeat run) into the plan's human follow-ups. Keep the registration behind a seam
so the DB-free suite runs the shutdown release directly instead of ending the process.

## The amount check may not be replay-stable

The walk above found a fourth thing no reading had: the repeat can be **refused by a validation
the first call passed**. A handler that checks "paid amount ≥ what the basket requires" recomputes
the requirement on the repeat — and the first, half-completed call may have changed it: a credit
or voucher it consumed no longer reduces the total, so the same payment is now "too small". The
record whose claim was released never heals, and neither code path is wrong in isolation. Before
promising "the repeat confirms it", ask of every precondition the handler evaluates: *does a
partially completed first call change its inputs?* Walk one fixture per credit-like input.
Whether to fix it belongs with the handler's owner; recording it as a known residual is the
minimum.

## Related

- [`COMPARE_AND_SET_GUARD_SCOPE.md`](COMPARE_AND_SET_GUARD_SCOPE.md) — the claim itself: guard
  scope, rows changed vs matched, hooks fired by key.
- [`RECHECK_OUTBOUND_GUARDED_WRITE.md`](RECHECK_OUTBOUND_GUARDED_WRITE.md) — the alternative when
  an adapter of the gated call reads the claimed column: re-check, call, guarded write, reported
  miss.
- [`STATE_WATCH_ON_A_SHARED_CHECKOUT.md`](STATE_WATCH_ON_A_SHARED_CHECKOUT.md) — the fan-out variant:
  a periodic watch whose claim gates several independent effects — isolate each effect, restore only
  a claim whose effects never started, name each effect's own fallback instead of a release.
- [`REVERSIBLE_EXPIRY_ON_TWO_PHASE_HOLDS.md`](REVERSIBLE_EXPIRY_ON_TWO_PHASE_HOLDS.md) — the
  marker-conditional single-statement un-cancel: the same "undo only the bare state" shape.
- [`../../work/references/EXECUTE_OVER_PIN.md`](../../work/references/EXECUTE_OVER_PIN.md) — why
  the heal is walked, not pinned.
