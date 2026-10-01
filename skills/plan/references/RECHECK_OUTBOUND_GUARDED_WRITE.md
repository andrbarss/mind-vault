# Re-check, outbound call, guarded write — closing a two-writer race when an adapter reads the state

Load when a plan closes a race between a **sweeper** (an expiry cron, a reaper, a reconciliation job)
and a **confirmer** (a payment callback, a sync import) that both read a row's state, make a slow
outbound call (a PMS, a payment provider, a mail transport), and then write the state with
`WHERE key = ?`. The obvious fix — claim the transition first, then make the call
([`CLAIM_BEFORE_SIDE_EFFECTS_NEEDS_A_WAY_BACK.md`](CLAIM_BEFORE_SIDE_EFFECTS_NEEDS_A_WAY_BACK.md)) —
is the right tool only when nothing downstream of the claim reads the column it changed. The field
case here had an adapter that did, and the claim-first draft was rejected in architect review for it.

## The shape

The sweeper reads a candidate list once, then per row: outbound cancel → `UPDATE … SET state =
cancelled WHERE key = ?`. The confirmer reads the row, pushes to the external system, then
`UPDATE … SET state = confirmed WHERE key = ?`. Three interleavings, two of them silent:

| Order of events | End state |
|---|---|
| sweeper lists R → confirmer completes → sweeper reaches R minutes later | confirmed, then cancelled over it — **no tight timing needed**; the list is one outbound call per earlier row old |
| sweeper is inside its outbound call for R → confirmer writes → sweeper writes | same |
| confirmer has read R → sweeper cancels R → confirmer writes | the confirmer's "re-open" branch, if it has one; otherwise the same |

Nothing connects the two: an idempotency lock keyed by the confirmer's request id is invisible to
the sweeper. On a storage engine without transactions (MyISAM) there is no row lock to take either.

## Audit the adapters before moving the write

The claim-first design — `UPDATE … SET state = cancelled WHERE key = ? AND state = pending`, then
the outbound call, release on refusal — closes every interleaving on paper. Before adopting it,
**open every adapter the outbound call dispatches to and grep for reads of the column the claim
changes.** The field case: one of six adapters re-read the table with `state != cancelled AND
external_id = ?` to decide between "cancel the whole external booking" (one row left) and "re-send
the rows to keep" (several). With the local row already cancelled, a one-room booking stayed live in
the external system and a two-room booking was cancelled whole. Every expiry on that adapter, no
race required. The other five adapters used only the array they were handed; they were not the
problem, and reviewing them does not clear the sixth.

A claim placed before an outbound call also adds windows the legacy order did not have: a process
that dies between the claim and the answer leaves a row the sweeper never lists again (it lists
`pending`, the row says `cancelled`); a refusal during a concurrent confirmation sends the row back
to pending while the confirmer, which no longer lists it, has already charged the customer. Write
the better / same / worse table before choosing.

## The order that keeps the adapters whole

When any adapter reads the column, keep today's order and add a check on each side of the call:

1. **Re-check immediately before the outbound call** — one `SELECT … WHERE key = ? AND <the whole
   candidate predicate>`, evaluated by the database. A row paid, held, restored or already
   cancelled since the list was read gets no call and no write. This closes the stale-list window,
   which is the one that needs no timing.
2. **Guard the write** — `UPDATE … SET state = cancelled WHERE key = ? AND <still in the state the
   decision needs>`. One statement; atomic on MyISAM as on InnoDB. A confirmation that landed
   during the call changes the row to confirmed; the sweeper's write then matches nothing, and the
   row stays confirmed.
3. **Classify a write that changed nothing — never retry it.** Read the row by key: cancelled by
   another sweep in the meantime (two runs, or the storefront's own expiry) is a benign outcome,
   counted and answered as success; anything else is the residual — the external booking is
   cancelled while the local row is confirmed — logged with the key and the external id, and mailed
   to the people who can re-register it. Make the report unable to throw: it runs after the
   outbound call, and a mail-transport failure must not abort the sweep or turn the confirmer's
   answer into a 500.
4. **Fire the post-update hook by key.** A base-model hook that re-selects "the row just updated"
   with the caller's `WHERE` never sees it once the guarded column moved
   ([`COMPARE_AND_SET_GUARD_SCOPE.md`](COMPARE_AND_SET_GUARD_SCOPE.md) § 2).
5. **No elapsed condition in the write.** Once the external system cancelled, a row that is still
   pending is cancelled locally even if its expiry moved during the call; refusing the write there
   leaves a payable row whose external booking is gone.

What stays open, and must be written down as a residual: a confirmation whose write lands during
the sweeper's outbound call ends confirmed locally and cancelled externally. It is reported, not
prevented. Closing it needs either the claim (rejected above) or an external re-create.

## Guard on the state the decision needs, not the value you read

The natural guard is `state = <as read>` — "guard what the computation read". It is too narrow when
a **benign transition** exists between two states the decision treats alike: a row read as
*created* that became *awaiting payment* during the outbound call is still unpaid, and its external
booking is gone by then. `state = created` matches nothing; the row is left live and payable,
reported as "changed during cancel" — the state the design exists to refuse. The guard is the set
the decision admits (`state IN (created, awaiting_payment) AND invoice <= 0`), and the pure
predicate that decides eligibility in code must admit exactly the same set — test the two against
each other. Build the guard before the outbound call, from nothing that can throw after it.

## The confirmer's side: a hold, on every clock that judges it

The confirmer can keep the sweeper away for the length of its own work with one statement at entry
— before it restores or reads anything — that moves the expiry of the rows it is about to confirm
at least N minutes ahead, never shortening a later one. With the sweeper re-checking at write time,
the hold is honoured by construction. Three things decide whether it is correct:

- **Which clock judges the column.** The sweeper compares the expiry with the database's `NOW()`;
  the cart readers compare it with the application's clock; on the dev stack the two differed by
  three hours. Write the later of "now + N" on both —
  `GREATEST(DATE_ADD(NOW(), INTERVAL N MINUTE), '<app now + N>')` — and probe the database arm
  separately, because on a skewed stack one arm always wins and the other is never exercised.
- **Rows without the column.** A row whose expiry is NULL is judged by its creation time plus a
  configured interval; the hold must use the same interval, from the same configuration key the
  sweeper reads, or it leaves exactly those rows unprotected. Check the model actually has access to
  that configuration — in the field case it read a property nobody ever assigned, so its own
  fallback silently governed.
- **It must fail open.** A protection inserted into a payment path is not a step of the payment: a
  failing statement is logged and the callback continues. In the field case a throw there would
  have left the callback's idempotency lock set, so the processor's repeat would have been answered
  "already processed" and the paid cart never confirmed. Write it through the table's plain update
  so no re-sync stamp or event fires for a column that only moved.

A hold placed in two callbacks protects only those two; list every other confirmer (a channel
API, a worker that confirms what it just created) and say which of them the sweeper-side guard
still covers (all of them — only the hold's narrowing is callback-specific).

## Walking it

The race cannot be timed from outside; neither can the adapter refusal on a dev stack with no
external system. A scratch subclass of the model, driven by a throwaway controller on the branch's
own stack, with the outbound call replaced by a script that **changes the row during the call**
(pays it, cancels it, moves its expiry, pays a sibling), reaches every interleaving
deterministically and against the real driver. The default branch on a second stack over the same
database is the "before": the same probe there, with the second writer placed between the legacy
read and write, shows the state being reported. Fixtures carry ids below the table's
`AUTO_INCREMENT` in a range no table used; delete-triggers that log rows are cleaned by the
fixture ids afterwards; the sweeper action itself is never run on a shared database that holds
genuine candidates — drive the model method per id instead.

## Related

- [`CLAIM_BEFORE_SIDE_EFFECTS_NEEDS_A_WAY_BACK.md`](CLAIM_BEFORE_SIDE_EFFECTS_NEEDS_A_WAY_BACK.md) — the
  design this one replaces when an adapter reads the claimed column.
- [`COMPARE_AND_SET_GUARD_SCOPE.md`](COMPARE_AND_SET_GUARD_SCOPE.md) — the guard itself, the hook by
  key, rows changed vs matched.
- [`REVERSIBLE_EXPIRY_ON_TWO_PHASE_HOLDS.md`](REVERSIBLE_EXPIRY_ON_TWO_PHASE_HOLDS.md) — the reaper
  re-applies its predicate at the write; the cutoff on the clock that writes the column.
- [`../../work/references/LIVE_BEFORE_ORACLE.md`](../../work/references/LIVE_BEFORE_ORACLE.md) — the
  default branch as the "before".
