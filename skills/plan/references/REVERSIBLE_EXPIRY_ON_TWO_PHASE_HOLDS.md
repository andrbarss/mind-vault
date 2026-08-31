# Reversible expiry on two-phase holds — the reaper releases a hold someone still trusts

Load at `/plan` (or architect review) whenever the design adds **an expiry mechanism to a
two-phase hold**: a reaper, a sweeper, a TTL job, an "auto-cancel after N minutes" cron over
rows that some other code path treats as a reservation of a scarce resource.

## The shape

A two-phase flow holds a scarce resource with a row. Phase 1 creates it — a cart line, a seat
hold, a provisional booking, a quota grant, a pending invitation — and the availability
calculation **subtracts that row** from what's sellable. Phase 2 confirms it, and a worker
materialises the real record.

Rows that never reach phase 2 hold the resource forever, so someone proposes a reaper. The
moment a reaper exists, a confirmation that arrives *after* it has to be able to undo it —
"expire aggressively" and "never lose a late payment" pull in opposite directions, and the
obvious implementation of each breaks the other.

## The four traps, in the order they bite

### 1. The reaper released a hold a downstream writer still trusts

This is the one that gets missed, and it is the expensive one. Find the code that materialises
the confirmed row and read its arguments. In a mature two-phase flow it almost always **skips
the availability check on purpose** — `create(..., ignore_availability=True)`, `force=True`,
`skip_validation=True` — because the hold row *was* the check. That flag is a contract: "the
caller already proved this is available."

A reaper breaks that contract silently. It releases the hold, the resource is resold, and a
late confirmation re-enters a write path that **will not look**. The result is an overbooking
with no error anywhere.

So: **the revival site re-validates what the expiry released** — not the worker. The worker's
skip-the-check contract is relied on by every other caller and must stay as it is. Grep every
caller of that writer before touching its guard.

Re-check everything phase 1 validated, not just capacity: start dates that have since passed,
external ids that were re-used in the meantime, anything with a freshness window.

### 2. The capacity re-check must be demand-aware, not per-row

A cart with two rows for the same resource on the same night, and one unit free, passes a
per-row check **twice**. Group the revivable rows by resource key, expand each to the units it
consumes (nights, seats, slots), and require `demand[unit] <= free[unit]` — aggregate first,
compare once.

Two absent-data cases need separate answers, and conflating them is a bug: the key is missing
from the availability map (genuinely no inventory → block) versus the key is present but the
capacity field is absent (the deployment has that accounting disabled → pass, and log it once
so the silence is visible).

### 3. An unconditional un-cancel erases a deliberate cancellation

If confirmation clears the cancel flags whenever it lands, it also erases a cancel the customer
or the channel made **on purpose** — silently, and in favour of taking their money.

Fix: **namespace the reaper's cancel with a marker** in the attribution column that already
exists (`cancelled_by`, `closed_by`, `voided_by`). Every human/system writer puts a *name*
there; a reserved prefix (`cron:`, `system:`) is disjoint from all of them by construction, so
"did *this* mechanism cancel the row?" becomes a total, local question. Then make the un-cancel
conditional on the marker.

**Grep every writer of that column before claiming disjointness.** A design that asserts "this
is only cancelled in one place" is a negative-existence claim and deserves the same scepticism
as any other — the field case had *two* writers (a request handler and an async queue drain
serving the same API call), and the second was found only by a claim-vs-code pass. A cheap
test locks the invariant: assert the marker's prefix, and scan the source for any other cancel
call passing a literal with that prefix.

### 4. Splitting the un-cancel into two statements re-opens the reaper's own predicate

`revive()` then `confirm()` leaves an intermediate state that is *exactly* what the reaper
selects for (uncancelled and unconfirmed). A concurrent reaper run lands in the gap and
re-cancels a row that is mid-confirm.

Do it in **one** statement — the confirm's own UPDATE carries conditional expressions:

```sql
UPDATE holds
   SET confirmed = 1,
       confirmed_at = NOW(),
       cancelled = IF(cancelled_by = :marker, 0, cancelled),
       cancelled_at = IF(cancelled_by = :marker, NULL, cancelled_at),
       cancelled_by = IF(cancelled_by = :marker, NULL, cancelled_by)   -- LAST
 WHERE id = :id
```

**Assign the discriminator column last.** MySQL evaluates a single-table UPDATE's SET list
left-to-right *using already-updated values*, and ORMs generally emit the pairs in the order
the caller supplied them. Put `cancelled_by` first and the following two comparisons test
against `NULL` and never fire — a silent no-op that no test catches unless it asserts the
post-state of all three columns together. This ordering is load-bearing; comment it in the
source or a later "simplification" will reorder it. (See also the DB-integrity bullets in the
curator's PASS 4.)

## Two more things the design must settle

**The reaper re-applies its whole predicate at the write, not just the ids it selected.**

```sql
UPDATE holds SET cancelled = 1, cancelled_by = :marker, cancelled_at = NOW()
 WHERE id IN (:ids) AND <every flag condition> AND created_at < <db-evaluated cutoff>
```

The preceding SELECT only bounds and logs the run. A row confirmed between select and write
fails the flag condition at the write and is left alone — so the classic select-then-act race
needs no lock, and two overlapping runs cannot double-cancel (the second's affected-count is 0).

**The cutoff is evaluated by the database** whenever the timestamp column is written by the
database (a `CURRENT_TIMESTAMP` default). An app-computed cutoff compared against a DB-written
column is a cross-clock comparison; wherever the two clocks differ, it reaps rows that are
still live. Write `created_at < DATE_SUB(NOW(), INTERVAL :n MINUTE)` — the interval, validated
as an integer, is the only thing that crosses the boundary.

## Revival is all-or-nothing, and says why

A partially-revived cart behind a `success` response hides a money-relevant outcome. Refuse the
whole set, name the blocked ids, give the reason per id, and **name the exit** — the endpoint
or action the caller should invoke to clear the blocked items and retry. "Silently skip the
blocked item" is the tempting default and it is wrong.

The marker doubles as the pin that makes that exit work: widen the deliberate-cancel paths to
accept marker rows (`WHERE ... AND (cancelled = 0 OR cancelled_by = :marker)`), so a caller
cancelling a reaped row succeeds idempotently and **overwrites** the attribution with its own
name — which blocks revival by construction, with no extra flag.

## Plan-time checklist

- [ ] Named the writer that materialises the confirmed row, and read its availability-check argument.
- [ ] Revival re-validates capacity **and** every other phase-1 precondition, at the revival site.
- [ ] Capacity check aggregates demand per resource-unit before comparing.
- [ ] Missing-key and missing-capacity-field cases have distinct, deliberate answers.
- [ ] Reaper's cancel carries a reserved marker; every writer of that column was grepped.
- [ ] Un-cancel is marker-conditional and lives in the confirm's own statement, discriminator column last.
- [ ] Reaper re-applies its full predicate at the write.
- [ ] Cutoff is evaluated on whichever clock writes the timestamp column.
- [ ] Revival is all-or-nothing, with per-id reasons and a named exit.
- [ ] Deploy order: the widened cancel paths ship in the **same release** as the reaper, and the
      schedule is enabled **after** the code deploy. Old code answers "not found" for marker rows.

## Related

- `skills/plan/references/VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md` — the same instinct applied
  to claims the plan makes about existing behaviour.
- `rules/RULE_self-sweep-before-push.md` trigger 3 (a guard that skips or discards rows is a
  data-shape claim) and trigger 5.7 (negative-existence claims are grep-verified before they land).
- `agents/AGENT_curator.md` PASS 4 — the two DB-integrity bullets this design leans on.
