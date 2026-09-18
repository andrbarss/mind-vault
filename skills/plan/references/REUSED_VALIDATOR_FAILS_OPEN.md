# A reused validator fails open on a failed lookup — and fail-closed has an edge too

Load when a plan **re-runs an existing validator on a new path** — a stock / quota / sales-window /
eligibility check that today runs only at creation, now also needed on an update, a resize, a
re-price, a transfer. The reuse is right (one copy of the rule). The trap is in what the validator
was never asked at its original call site.

## 1. Lookups answer `false`; validators written for arrays pass on it

Legacy validators are written against the happy shape: `isset($thing['limit']) && $thing['limit'] <
$used + $n` → invalid, else valid. Feed them what a failed lookup returns — `false`, `null`, `[]` —
and every guard is skipped: **the validator passes**. At the original call site this never showed,
because creation dereferences the looked-up thing earlier and dies loudly (or creates an obviously
broken record) when it is missing. The new path has no such earlier dereference, so a deactivated
item, a deleted item or an **unreachable catalogue** (a remote adapter that swallows its exception
and returns `false` after a timeout) yields an unchecked pass.

Demand at plan time:

- **Read the lookup's failure return and the validator's behaviour on it** — both adapters when
  there are two (a local table reader and a remote HTTP one usually differ in *when* they fail, not
  in *what* they return). Write the pair into the plan: "lookup → `false` on X, Y, Z; validator →
  passes on `false`".
- **A pure verdict in front of the validators**: not loadable / not the expected shape → refuse
  with its own reason, before any validator runs. Pure, so its truth table is unit-tested
  (`false`, `null`, `[]`, a row without the discriminating key, a key that is not text).
- **Scope parity with the counter.** If the "used" figure is filtered (per tenant, per system, per
  channel) and the row being changed is loaded without that filter, a foreign row makes the
  arithmetic inexact — the counter excludes what the delta assumes it includes. Refuse the foreign
  row rather than compute a wrong delta.
- **Validate the delta, not the new total**, when the counter already includes the row's current
  quantity — and only on an increase. Check which statuses the counter treats as holding stock
  before deciding which states may be resized.

## 2. …but fail closed on *could not load*, not on *loaded and not the counted type*

The over-correction is as real as the hole. A record can carry a "this is a ticketed thing" flag
that the *caller* supplied at creation and the creator stored as given — on an item of a type for
which **no check ever runs**. A verdict that refuses everything that is not the counted type then
refuses every increase on such a record, permanently, for a limit that does not exist.

Before writing "type ≠ counted type → refuse", grep for where the limit is actually enforced at
sale time. If it is enforced for one type only, then:

- *lookup failed* / *foreign scope* → refuse (nothing can be judged);
- *loaded, counted type* → run the validators on the delta;
- *loaded, any other type* → **allow**: there is nothing to count, and the new path must not be
  stricter than the sale was.

State the three rows in the plan and in the operation text; the middle-severity reviewer instinct
("fail closed everywhere") will otherwise re-tighten the third row later.

## Verification

- Truth tables for the verdict and the counted-type predicate (executed, DB-free).
- Source pin: the verdict precedes the validators; the validators receive the delta.
- Live: an increase within stock, one beyond it (the validator's own message), a decrease (no
  validator), an item whose lookup fails (refused), and a flagged record on a non-counted type
  (allowed).

## Related

- [`LIST_ENDPOINT_OVER_A_SINGLE_TARGET_EVALUATOR.md`](LIST_ENDPOINT_OVER_A_SINGLE_TARGET_EVALUATOR.md) —
  reusing an evaluator from a second call site, the read-side sibling.
- [`PRODUCER_ARGUMENT_CONTRACTS.md`](PRODUCER_ARGUMENT_CONTRACTS.md) — the scoping arguments a
  shared producer does or does not forward (the counter's filter above is one).
- `skills/work/references/AUDIT_NEWLY_REACHABLE_CODE.md` — the same class seen from the fix side:
  code that was never reached with this input before.
