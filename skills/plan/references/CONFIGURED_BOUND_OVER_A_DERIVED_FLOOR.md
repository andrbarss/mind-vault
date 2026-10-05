# A configured bound over a derived floor — replace or compose, which side fails closed, and the zero that rounding hides

Load when a plan adds **operator-configured bounds** (a minimum, a maximum, a quota) to a value
that already has a **structural** limit the code derives from data — a floor that is "the listed
price", a cap that is "the stock", a ceiling that is a column width. The field case: a sale for a
customer-chosen amount whose only floor was the sold item's own price row (a price that was never
meant to be a floor) and whose only ceiling was the column's technical maximum; the owner wanted
two optional tenant properties, published by the listing endpoint and enforced by the sale. Four
decisions in that plan looked obvious and three of them were wrong on the first draft; an
independent review after the engine read CLEAN found the fourth.

## 1. Replace or compose — ask the owner, then keep the structural gate

Two readings of "the minimum is now configurable" both sound right:

| Reading | Effective floor | Who it serves |
| --- | --- | --- |
| **Compose** | `max(derived, configured)` | the derived floor keeps meaning something ("never below the listed price") |
| **Replace** | `configured ?? derived` | the operator's number is *the* number; the derived value is only the default |

The plan's architect leaned to compose (the derived floor was "the one gate the listing and the
sale share"); the owner chose **replace** — "they replace previous conditions". Neither is
derivable from the code: it is a product statement about what the operator's field *means*. Put
it as the first owner question, with both readings spelled out as a table, and write the answer
into the requirement list as its own numbered line.

Whichever is chosen, **the structural gate that made the derived value exist stays**: a replaced
floor still requires the price row to *exist*, because that row is also the listing's join and
the sale's "misconfigured" check. "Replace the value" is not "drop the gate". State that in the
decision, or a reader of "replace" will delete the existence check too.

## 2. The two directions do not fail the same way

Garbage in an operator-typed bound (`20,5`, `5OO`, a stray letter) has to go somewhere. The
precedent in the codebase said "unparseable = disabled" for an id-shaped property, and the first
draft copied that shape for both bounds: unparseable ⇒ unset. For the **floor** that is harmless
(the derived floor returns). For the **ceiling** it silently removes the only product cap on a
money amount — the opposite of the owner's fail-closed choice for the max-below-min case made in
the same plan. The reviewer's test: *what does "unset" cost on each side?* A missing floor costs
one under-priced sale; a missing ceiling costs an unbounded one.

Resolution the owner chose: **asymmetric** — an unusable minimum is unset; a *non-empty*,
unusable maximum refuses every sale with its own text. "Non-empty" is a separate predicate from
"usable" (`''`, whitespace and a zero are unset; `abc`, a negative, an over-ceiling number are
set-but-unusable). Give the misconfiguration its own refusal key and text: it is the one
misconfiguration the operator can fix alone, and reusing the generic "not configured" text hides
it. Write the asymmetry into both property descriptions.

## 3. A fail-closed decision needs its sentence on the read surface

The sale refuses while the listing publishes the same tenant as healthy: an unusable maximum is
`null` on the wire ("no ceiling") and every submit fails. The behaviour was the owner's decision;
the **published contract was silent about it**, which the independent review flagged (the engine
did not — it reads diffs, not the gap between two surfaces). Every time a write path fails closed
on configuration, grep the read path's schema / docblock / consumer contract for the state the
write refuses in, and add the one clause: "a configured maximum that is not a number is `null`
here and refuses every sale the same way." A client reading `null` as "unbounded" then knows the
refusal is a configuration error, not its bug.

## 4. A normaliser that rounds must test zero on the rounded value

`bound()` delegated to the existing amount rule (numeric, finite, `> 0`, `<= ceiling`) and then
rounded to cents. `'0.004'` passes `> 0`, rounds to `0.00`, and comes out as a **set** bound of
zero — a floor of nothing, or a ceiling that refuses every amount with "above the maximum (0)".
The request-amount path next to it already guarded exactly this (`round` first, then `<= 0` ⇒
invalid); the bound path, written a week later from the same rule, did not — the tell was a
`'rounds to zero'` row in the request path's data provider that the bound path's provider lacked.

Two rules: (a) **every predicate that follows a rounding step evaluates the rounded value** — the
emptiness / zero test, the "set but unusable" test, the comparison with the sibling bound; (b)
**when a new path reuses a sibling path's rule, diff the two data providers** — a row the old
path has and the new one lacks is a guard the new path is missing (the self-sweep's
guard-return-asymmetry trigger, applied to normalisers).

## 5. Operator-facing text is read for years; a deploy gate is read once

"Leave empty until the backend that reads it is deployed" is true for the deploy window and false
forever after, and a registry description seeded by a migration is the only text an operator sees
on that screen — nothing ever removes the sentence (a later stem could only rewrite it by
equality on the seeded text). The gate belongs in the migration header, the migrations index and
the PR; the description names the rule exactly ("a positive amount up to <ceiling>; empty or 0 =
no maximum; a value that is not such an amount, or below the minimum, stops every sale until
fixed"). The same test as the spec-text rule for API descriptions: process wording describes a
moment, durable text describes the surface.

## 6. Repairing what an earlier stem seeded

The feature made the *earlier* IDEA's stored operator text false ("its price row is the
minimum"). The applied stem is content-hashed and never edited; the data it wrote is not — the new
stem carries one more statement: `UPDATE … SET description = <new> WHERE property = <key> AND
description IN (<every seeded text so far>)`. Equality on the seeded texts preserves an
operator-written description (the same convergence contract the seed itself used); the down-file
restores the latest seeded text where the description equals the new one; the header names the
stems whose data it amends and the commit trailer carries the amendment. The walk proves both
directions and the operator-edited case: set a custom text, roll back, re-apply, read it back
untouched. [`../../../rules/RULE_cross-idea-amendments.md`](../../../rules/RULE_cross-idea-amendments.md)
has the file-level rule; this is its data-level corollary.

## 7. What to pin, and what the wire says

- The verdict carries both bounds (`minimum`, `maximum`) so the refusal text can quote the one
  that fired; the pin on the shape of the verdict array gains the key.
- Bounds enter the decision as a **lazy callable read after the structural gate** — a legacy
  request and every earlier refusal still read nothing; a throwing callable in the tests proves
  it, and a counting callable proves "once".
- A whole amount serialises as a JSON **integer** on this stack (`json_encode(20.0)` → `20`), so a
  schema pin on "a number" accepts int or float and refuses a string — never `assertIsFloat` on
  a value that was derived from a column, and never a literal.
- The listing's per-row value when the configured minimum is unset is **that row's own** derived
  value (one listing element per price row), not the one the sale will use (the newest row) —
  state the difference in the schema text rather than reconciling it in code.

## Checklist for the plan

- [ ] Replace vs compose put to the owner as a two-row table; the structural existence gate kept
      either way, said explicitly.
- [ ] Per direction: what "unset on garbage" costs; the ceiling fails closed; "non-empty" and
      "usable" are separate predicates; own refusal key + text for the misconfiguration.
- [ ] The read surface's contract names every state in which the write refuses on configuration.
- [ ] Every predicate after a rounding step runs on the rounded value; the new path's data
      provider is diffed against the sibling path's.
- [ ] Deploy-window sentences stay out of seeded operator text; the text names the exact rule.
- [ ] Data seeded by an earlier content-hashed stem is repaired by the new stem with equality on
      the seeded texts, reverse in down, the operator-edited case walked.
- [ ] Bounds read lazily after the structural gate (throwing + counting callables); wire type of
      a derived number pinned as int-or-float.
