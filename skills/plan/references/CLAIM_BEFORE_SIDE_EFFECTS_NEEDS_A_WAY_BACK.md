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
- [`STATE_WATCH_ON_A_SHARED_CHECKOUT.md`](STATE_WATCH_ON_A_SHARED_CHECKOUT.md) — the fan-out variant:
  a periodic watch whose claim gates several independent effects — isolate each effect, restore only
  a claim whose effects never started, name each effect's own fallback instead of a release.
- [`REVERSIBLE_EXPIRY_ON_TWO_PHASE_HOLDS.md`](REVERSIBLE_EXPIRY_ON_TWO_PHASE_HOLDS.md) — the
  marker-conditional single-statement un-cancel: the same "undo only the bare state" shape.
- [`../../work/references/EXECUTE_OVER_PIN.md`](../../work/references/EXECUTE_OVER_PIN.md) — why
  the heal is walked, not pinned.
