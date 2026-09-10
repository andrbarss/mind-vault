# A writer rule stricter than the storage contract needs a client exit — and an amended contract needs one authoritative delta

Load when a plan adds a **validation rule the storage does not enforce** on a write path whose
**read-back is faithful** — an "at least one of these flags must be on", "a non-empty list", "a
value inside the allowed set" — over a table another system, a migration, a seed script or a
hand-run `UPDATE` can also populate. Also load when the plan **amends a contract another codebase
already builds against** (the consumer side of `SCHEMA_CONTRACT_HANDOFF`): the second half of this
file is the delta-with-pointers shape that keeps the two copies from drifting.

## The trap: legal storage, refused write, faithful read

Field case (an admin API writing display-placement flags onto per-value rows a storefront reads).
Three facts, each correct alone:

1. The storage contract (owned by the reader's repo) keeps the all-`false` triple a **legal
   state** — "the item is filled in but shown nowhere, its values kept". Seed scripts and a
   drifted pair can produce it; the writer's own contract says the writer *never* produces it.
2. The owner rules "at least one flag must always be on", so the writer **refuses** an
   all-`false` entry with a field error. One rule, no carve-outs — the clean design.
3. The read-back is **faithful**: it returns whatever the rows hold, including the all-`false`
   triple the writer would refuse.

Compose them as the consuming UI would: the form seeds its checkboxes from the read-back, the
user saves, the form re-sends every entry it was given — and the stored all-`false` entry is
refused on every save. For an *active* item the user can tick a box and move on. For a
**retired** item — one the same contract says must be re-sent unchanged, behind *disabled*
checkboxes — there is nothing to tick: **every save of that parent record is refused with no
control that changes the outcome.** The precise failure the same writer's own "a UI that always
sends everything must never 400 forever on a record it cannot fix" rule was written to prevent.

None of the three rules is wrong. The composition is. It is invisible per-file and per-rule; only
walking the seed → save → refuse loop as a naive implementer exposes it (`SCHEMA_CONTRACT_HANDOFF`
§ composability check — this is that check applied *across* the storage contract, the writer's
contract and the read-back).

## The exit, decided at plan time

Every write rule that is stricter than storage owes the plan an answer to one question: **when a
client reads back a state this rule refuses, how does it get out?** Three shapes; pick one and
write it into the contract the consumer builds against, not into a comment.

| Exit | Where it lives | When it fits |
| --- | --- | --- |
| **Seed rule on the consumer** — "if a seeded value violates the rule, normalise it at seed time and mark the entry dirty, disabled rows included" | the consumer-facing contract's UI-guidance section, marked *load-bearing* | the refused state is rare, storage-only, and the writer wants exactly one rule (the field case: tick the default placement on an all-`false` seed) |
| **Carve-out at the writer** — exempt the class of entries the client cannot edit (retired / read-only rows carry their value through as sent) | the writer, in the phase that already knows the entry's class (the existence/status check, not the DB-free parser) | the consumer is not yours, or several consumers exist and one seed rule per consumer is worse than one branch |
| **Coerce** — silently repair the refused state on write | almost never | the rule is a *storage* invariant with no user intent behind it; a client's explicit value must not become silently untrue |

Record the chosen exit **and** the fallback: "closed on the UI side by contract § N; a writer-side
carve-out in `<phase>` is the recorded fallback if a client without the seed rule ever hits it".
The fallback matters because the seed rule lives in code you do not ship.

Checklist before the plan locks:

- [ ] For each rule the writer enforces that the DB does not: name every way the refused state can
      still reach storage (other repo's seed, migration default, hand `UPDATE`, drift on a
      multi-row pair). If the answer is "none", say so and cite the grep.
- [ ] For each such state: what does the read-back emit? Faithful (the trap) or normalised
      (hides the state — the storefront and the admin then disagree on the same rows)?
- [ ] For each entry class the client re-sends **unchanged** (retired, read-only, locked): can it
      carry the refused state, and what does the client do then?
- [ ] The exit is written in the consumer contract's own words, with the retired/read-only case
      named explicitly — a seed rule that forgets disabled rows closes nothing.
- [ ] A test pins the faithful read-back of the refused state (so the trap stays visible) and a
      test pins that the writer refuses it (so the exit stays load-bearing).

## Amending a shipped contract: one authoritative delta, pointers in the amended file

When the new rules change a contract a sibling codebase already builds against, the temptation is
to rewrite the affected sections in place *and* ship the new idea's own contract. Two copies of
the same prose drift within a sprint. The shape that held:

- The **amending idea's contract is the authoritative delta** — the amended sections in full
  (read-back shape, write rules, exact message texts, the new degrade row, the UI guidance),
  with a header saying what it is a delta over and that everything not restated is unchanged.
- The **amended contract gets pointers only**: one header line ("amended by … — the amended text
  lives in one place: `<path>`; each section below points there") and a one-line pointer in each
  affected section. No duplicated rules, no duplicated message texts.
- The amending idea's plan lists both files as plan-stage deliverables, and its `/wrap` writes
  the cross-idea backref into the amended idea's archive.
- Every rule the consumer must own (the seed rule above; "send every key on every entry")
  is in the **delta's** UI-guidance section — the consumer reads one file.

The consumer then codes against the delta and re-reads it at the end of its own `/work`
(`CONTRACT_CONSUMER_DISCIPLINE`), which is one file, not a diff of two.

## Anti-patterns

- ❌ "One rule, no carve-outs" declared without asking how a client escapes the refused state — the
  rule is clean on the writer and a lock on the consumer.
- ❌ A seed rule that handles editable rows and forgets the disabled ones — the disabled rows are
  the only ones that trap.
- ❌ Normalising the read-back so the refused state never shows — the reader in the other repo
  still sees the raw rows; the two surfaces now disagree on the same data.
- ❌ Coercing on write "to be helpful" — a client's explicit `false` silently becomes `true`.
- ❌ Rewriting the shipped contract's sections in place *and* restating them in the new contract
  — two copies, one sprint, guaranteed drift.
