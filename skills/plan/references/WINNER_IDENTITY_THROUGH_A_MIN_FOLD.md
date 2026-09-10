# WINNER_IDENTITY_THROUGH_A_MIN_FOLD

Load when a plan makes a reducer that already reports a **minimum / maximum / best** (a from-price,
a cheapest slot, a top score) also report **which candidate produced it** — "return the room type
behind the lowest price", "name the branch that won", "attach the id of the cheapest offer". The
number was always there; the identity was in the pipeline and thrown away at the last fold. Three
things break when the identity is bolted on without a plan, and none of them fails a test.

## The trap

A fold like

```php
foreach ($candidates as $c) {
    if ($lowest === null || $c['total'] < $lowest) {
        $lowest = $c['total'];
    }
}
```

keeps a number. Every candidate carried `hotel_id` / `room_type_id` / `food` (the producer joined
them in), and the fold dropped them. Naming the winner looks like a one-line change — keep `$c`
next to `$lowest` — and it is, *if* three facts are decided first:

1. **Which candidate wins a tie is now on the wire.** While only the number was reported, ties were
   invisible (equal numbers). The moment a name is attached, "first candidate wins on strict `<`"
   means *whatever order the producer answered in* — and a loader's `SELECT` with no `ORDER BY`
   (the common case for a map-building loader) answers in engine order. The flapping id will not
   appear in any test whose fixture is authored in sorted order.
2. **Two minima can come from two candidates.** A "cheapest stay" and a "cheapest single night"
   (or "best total" and "best per-unit") need not share a candidate. Track a winner per minimum;
   a single `$winner` variable silently names the last branch that fired.
3. **The identity you emit may ride on a uniqueness the schema does not enforce.** A resolved id
   (a relation-row id, a variant id) reached through a join of `(a, b) → id` is only "the" id when
   `(a, b)` is unique. If the table has just a primary key on `id`, the loader keeps the first row it
   met for the pair and the emitted id is plausible and wrong on a tenant with a duplicate — the
   worst kind of wire lie, because a consumer may *reserve* or *charge* against it.

## The rule

When a fold gains a source / winner / identity output:

- **Carry the winner, not the number.** In every branch that updates a minimum, set the winner
  beside it, one pair of variables per minimum; emit through one helper whose key order a constant
  pins (the schema pins the same constant). `null` exactly when the minimum is `null`, never an
  empty object.
- **Pin the tie-break in the reducer, never in SQL.** Sort the candidates on a tuple that is unique
  per candidate *by construction* (the keys the producer's map is built on — e.g. `(hotel, type,
  food)` when pairs and foods are map keys) and keep strict `<` first-wins in every fold. Do this at
  the stage every mode re-derives from: a "hard" / "engine" mode that re-prices the same candidates
  through another producer never sees the loader's SQL, so an `ORDER BY` there would pin only one
  of the two modes. Document the rule in one sentence on the schema ("on equal totals the lowest
  hotel id, then room type id, then food code wins").
- **State the unenforced invariant, probe it, don't widen the producer.** Write in the reducer's
  docblock that the emitted id relies on "one row per `(a, b)`", that the loader keeps the first
  row, and that a sibling endpoint already relies on the same thing. Add a plan verification row:
  `SELECT a, b, COUNT(*) FROM rel GROUP BY 1, 2 HAVING COUNT(*) > 1` → 0 rows on the reference
  data. A non-empty answer is a data-repair item, not a reducer change — consumer-scoped recovery
  is the wrong layer for a writer invariant.
- **Verify the name with an independent derivation.** Parity against the sibling endpoint that
  shares the reducer proves nothing (same fold, same drop). Walk a *different* producer's cells —
  the per-candidate price endpoint — take its cheapest, and check its own identity columns equal
  the emitted ones. Sibling of `VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md` § sign-to-magnitude
  promotion: a value promoted from "a number" to "a number *and who*" exposes everything the
  number alone absorbed.
- **Say when a tie cannot be observed.** Reference data with one priced candidate per parent has
  no tie; the unit tests are the gate. Write "no tie on the reference data by construction",
  never a fake probe row.

## Sibling trap: a pinned example couples the plan's commits

A shape constant that a spec / guard test pins against the schema **and against every element of
a committed example** turns "step 1: reducer, step 3: schema" into one commit: extending the
constant reddens the pin until the schema class, the example, and the pin's own count move
together. Before the plan splits steps into commits, grep the guard tests for the constants a
step extends and list what each pin walks — a pin that walks an *example* drags the annotation
file that carries the example into the same commit. Say so in the commit message and in the plan's
check-off; keep the folds that touch no pinned constant (the engine-mode fold) in their own commit.

## Checklist for the plan

- [ ] One winner variable per reported minimum; `null` iff the minimum is `null`.
- [ ] Candidates sorted on a by-construction-unique tuple *in the reducer*; strict `<` in every
      fold; the rule stated on the schema.
- [ ] Every emitted resolved id: the uniqueness it relies on is named as a writer invariant,
      probed on reference data, and not "fixed" in the producer.
- [ ] An independent-derivation verification row (a different producer, not the sibling that
      shares the reducer) and an honest "no tie observable" note where that is the case.
- [ ] Guard-test pins grepped before the commit split; example-walking pins fold the schema into
      the reducer's commit.
