# An additive column on a row with allow-listed writers — inventory the gates, normalise at the sink, one error shape per writer

Load when a plan adds a column to a table whose row is **written by several actions through explicit
allow-lists** (a validation form, a per-action `$fields` array, a placeholder row a reader fabricates,
a projection list an API applies) and **read by wholesale emitters** (`SELECT *` → JSON). A guest record,
a customer profile, an order line — any legacy row that grew a field at a time. The DDL is the easy
part; the work is the set of gates the value must pass on every path, and each one drops it silently.

## The rule

1. **Inventory every gate before writing the plan — and expect more than the obvious two.** Grep the
   table name, then the shared form, then every action that validates with it, then every reader that
   *names* columns. The field case had **five**: the shared form (only declared elements survive
   `getValues()`), two controller allow-lists that were copies of each other, a **placeholder row** a
   reader fabricates for not-yet-created entries (a key missing there makes placeholders and stored
   rows diverge on the wire — and a closed schema then fails on one of the two shapes), and a channel
   API's projection list. Readers that `SELECT *` need no code — say so in the contract, they are why
   "nothing reads it" was never a true negative
   ([WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md](WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md)).
2. **Pin the copied allow-lists identical.** Two actions carrying the same list by copy-paste drift the
   day one gains a name. A DB-free pin that loads both actions, parses both literals and asserts the
   sorted sets equal costs one test and outlives every future column.
3. **Normalise once, at the shared sink — because form validation does not mutate the caller's
   array.** `isValid($data)` sets the *filtered* values on the form's elements; the array the action
   goes on to write is untouched. An action that writes `getParams()` after validating therefore stores
   the raw value (`''`, padding, an array from `field[]=x`) even though the form declared a trim and
   a blank-to-NULL filter. When several writers converge on one save method, that method is the only
   place a "blank ⇒ NULL" invariant is true for all of them; put the normaliser there as a **pure
   static** (testable without the class's registry-bound constructor), guard it on key presence so an
   absent key still means "unchanged", and decide the non-scalar case explicitly (treat as blank, or
   refuse) with rows for it in the truth table. The form filter stays — it is what the writers that
   *do* use filtered values rely on — but it is not the guarantee.
4. **Choose the blank filter's mode on purpose.** A "null on empty" filter often defaults to an
   *all types* mode that also maps the literal `'0'` to NULL; on a free-text code that is a stored
   value, use the strings-only mode and pin it (`getType()`), noting that sibling elements keep the
   legacy mode. A solution doc that names the wrong constant for the default is itself a trap — verify
   the constant in the library source when you cite it.
5. **One error shape per writer, in the contract.** The same form refusal reaches the wire differently
   from each action that hosts it: a nested per-element map on one, a **flattened single string**
   (`"field: message"`) on the admin action another repo proxies, a code-not-message string on a
   channel API. A contract that says "the error arrives under `errors.<field>`" without saying *from
   which writer* sends the consumer's field-mapper after a key that never arrives. Walk one over-length
   value through **every** writer and quote each body verbatim in the contract's probe table
   ([SCHEMA_CONTRACT_HANDOFF.md](SCHEMA_CONTRACT_HANDOFF.md) § 3 / § 5).
6. **Teach the redaction guard before the first capture exists.** If the repo pins committed API
   captures against a PII key list, the new column's key joins that list in the *tests* commit, ahead
   of any capture commit — otherwise the first capture carrying a real value is green because the guard
   never knew the key. Add the value's real shape to the pinned redaction rows.
7. **Every spec-annotation change lands in one commit when a drift guard compares the committed
   artefact with a fresh scan.** An annotation added in the "code" commit without regenerating the
   artefact turns that commit red in CI even though the code is right; the review engine and a bisect
   both see a broken step. Sequence: DDL → writers/readers + tests (no annotation text) → other
   surfaces → **all** annotations + regenerated artefact + captures.
8. **Read the table's real charset and engine at step 0, not from a dump someone cited.** An
   `ADD COLUMN` inherits the *table* default; a capture-time claim ("InnoDB / utf8mb4") taken from a
   file that turned out not to exist in the tree would have made the charset pin look optional. One
   `information_schema` query settles it and belongs in the migration header.
9. **Distinguish "not walkable on this stack" from "not covered".** A session-gated admin action, a
   queue consumer disabled over HTTP, a channel whose token lives in a joined config table — each is
   either reached by a fixture you can build (a task row copied through a temporary table, a token read
   from the join) or stands on a source pin **plus** the shared-sink argument from rule 3. Say which
   in the transcript, per probe; a human-only residue is a recorded follow-up, not a gate.
10. **A derived rule in a model hook is a direct write that bypasses the unknown-column filter.** On a
    staggered per-tenant migration, a guarded-list ORM (Eloquent `$guarded`: `isGuarded()` consults
    the column listing) silently **drops** a mass-assigned key naming a column the tenant lacks. The
    owner's contract may predict "the save fails with *Unknown column*", but a ticked box instead
    vanishes at HTTP 201. The tempting place for a derived rule ("flag off ⇒ clear the window") is the
    model's `fill()` / save hook, as `$this->column = null`. That is a **direct attribute set**: it never
    passes the filter, so on an un-migrated tenant the `INSERT` / `UPDATE` names the absent column and
    the "fix" creates the 500 the silent drop was hiding. The hook also runs from every constructor
    and every caller, not just the endpoint that knows the tenant's schema. Put derived rules in the
    endpoint's pre-write decision instead. Emit their keys into the payload **only when the columns
    are provisioned**, and characterise the un-migrated behaviour live at step 0 (one request with the
    columns absent) before any text claims 1054 or silence. Field case: the capture proposed exactly
    that `fill()` rule, the plan caught it, and the step-0 probe measured the silent 201 the owner had
    written up as 1054.

## Why this is a plan-stage rule

Each gate reads as locally correct; the defect is a value that vanishes on *one* path and shows up
missing weeks later in a report nobody links to the form. The inventory (rule 1), the identical-list
pin (rule 2) and the sink normaliser (rule 3) are cheap only before the first commit — after it, each
missed gate is a review cycle. Rules 5–7 are the contract and commit discipline that let a sibling
repo and a drift-guarded artefact absorb the column without a second round.

## Related

- [SCHEMA_CONTRACT_HANDOFF.md](SCHEMA_CONTRACT_HANDOFF.md) — the contract this rule's error-shape and
  probe rows go into; the charset section.
- [WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md](WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md) — why the
  `SELECT *` readers are in the inventory even though no grep names them.
- [UNIQUE_KEY_TWO_LAYER_WRITER.md](UNIQUE_KEY_TWO_LAYER_WRITER.md) — the sibling discipline for a
  column that is unique (this rule covers the free-text, non-unique case).
- `../../work/references/EXECUTE_OVER_PIN.md` — the pure static normaliser is the executed test; the
  allow-lists and placeholder row are the pins.
