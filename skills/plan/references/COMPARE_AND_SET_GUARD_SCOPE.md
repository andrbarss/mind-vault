# Compare-and-set guard scope — guard what the computation read, fire the hooks by key

Load when a plan writes a value **computed from a row it read earlier in the same request** — a
re-price, a re-validation, a state transition decided by gates — and protects that write with a
conditional `UPDATE … WHERE <key> AND <expected state>` (optimistic concurrency, compare-and-set).
Three shapes, each correct-looking in isolation, make such a guard silently weaker than the plan
says it is. A design pass, an architect review and a pin all accepted the first two; an
independent post-implementation review found them.

## 1. The guard must cover every input the computation read — not just the identity

The natural guard pins the column the write *changes* ("still on the old plan", "still pending")
plus an eligibility column. That stops two concurrent transitions, but not the case a
compare-and-set exists for: another writer changes an **input** of the computation — dates, a
quantity, the product variant, a discount code, the channel that selects the price list — between
the read and the write. The conditional update still matches, and the row commits a value
computed for a state that no longer exists: 200, no error, no log line.

Demand at plan time:

- **Enumerate the columns from the computation, not from the write payload.** Walk every read the
  quote / validator / gates make on the row — including reads a shared helper makes on the
  caller's behalf (a grouping helper whose flag decides which id is priced; a lookup keyed by a
  parent id) — and make them the guard. A pure `writeGuard(row) → [column => expected]` beside the
  pure decision keeps the list reviewable and unit-testable, and a missing column in the row is an
  exception, not a silently narrower guard.
- **A NULL expectation is `IS NULL`.** Many query builders quote `null` as `''`, so `col = ?` with a
  null value never matches: every write on a row with a NULL input fails the guard and reports
  "changed by someone else". The guard becomes an outage instead of a hole. Build each clause
  explicitly — `value === null ? quoteIdentifier(col) . ' IS NULL' : quoteInto(quoteIdentifier(col) . ' = ?', value)`.
- **Compare what was read, as it was read.** Take expectations from the raw columns (a `SELECT *`
  row), never from values the loader decorated, localised or re-typed. A case-insensitive or
  space-padding collation can only make the guard match *more* — note it; it cannot cause a false
  refusal.
- **Refuse an empty guard** (`[]` degrades the statement to `WHERE key = N`): throw before writing.
- **Keep the domain out of the table gateway.** Pass the expected values and the eligible statuses
  in; a model that imports a feature's verdict class to read its constants couples persistence to
  one feature.

## 2. An after-update hook that re-reads with the caller's WHERE never sees the moved row

Base models and frameworks often run a post-update step that re-selects "the row just updated"
with the `WHERE` the caller passed — to fire an `updated` / `cancelled` event, reschedule
notifications, invalidate a cache. With a compare-and-set, that `WHERE` contains the **old** value
of a column the update just changed, so the re-select finds nothing and the hook returns early.
Nothing fails; the event simply never fires on this write path, and every future listener misses
it.

Demand: after a matched write (rows changed > 0), invoke the hook again **by key**
(`WHERE key = N`), and test that it is not invoked when nothing changed. Show the base update's own
hook cannot also fire (its re-select must provably miss — the guarded column always changes).
**Read the hook; don't trust the docblock.** "Goes through `update()`, so the event fires" was
written, reviewed and pinned before anyone traced the re-select.

## 3. Rows changed is not rows matched

Several MySQL drivers report *changed* rows unless the connection sets a found-rows flag, so a
compare-and-set whose payload can equal the stored values reads as "changed by someone else".
Either guarantee the payload always changes a guarded column (a state transition does), or read the
row back instead of counting.

## Verification

- An executed unit test through a recording double of the table: the `WHERE` equals the expected
  clauses (key, every guarded column, `IS NULL` for the NULL one, the status list); the hook is
  called by key once when one row changed and never when none did; an empty guard throws before
  any write. Quote in the double exactly as the real adapter does (ints bare, strings quoted) —
  otherwise the pin asserts text production never emits.
- Live: one write on a row with a NULL input (proves `IS NULL` against the real driver), one with a
  non-NULL input, and two identical writes fired together → exactly one success and one "changed".
- The stale-input race itself usually cannot be timed from outside the action. Say so in the plan
  and rely on the executed guard test — a "concurrent edit" probe that never lands inside the
  window is phantom verification.

## Related

- [`PRODUCER_ARGUMENT_CONTRACTS.md`](PRODUCER_ARGUMENT_CONTRACTS.md) § "The third error" — the
  computation's other half: which key the re-quote is allowed to forward.
- [`UNIQUE_KEY_TWO_LAYER_WRITER.md`](UNIQUE_KEY_TWO_LAYER_WRITER.md),
  [`WINNER_IDENTITY_THROUGH_A_MIN_FOLD.md`](WINNER_IDENTITY_THROUGH_A_MIN_FOLD.md) — sibling
  write-path and wire-identity contracts.
- `agents/AGENT_architect.md` PASS 3 — the reviewer-side bullet that points here.
