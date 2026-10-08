# Seeding settings another codebase consumes — read its writer, not its document

**Load when** a plan adds or seeds per-tenant setting rows whose only reader is **another codebase**. The
typical setup: a settings table that an endpoint emits wholesale; a consumer that fetches it and writes the
values into its own configuration (an env file, a config cache, a generated manifest). The usual source is a
list the consumer's team published ("keys the backend can send").

## The trap

The consumer's document said **"a non-empty backend value overrides the template default."** Its writer
ranked a value the operator typed in the consumer, then the value already in the tenant's file, then the
backend. That held for two keys, and they were the access-control pair: the console allow-list and the
console path token. The plan, the architect review and the implementation all trusted the document and the
consumer's *fetch* adapter, which showed what arrives and nothing about what wins.

By the time an independent review read the writer, these all promised effects the consumer never produces:
- the operator text on both rows;
- the rollback warning ("deleting the rows reopens the console");
- a security note on an unauthenticated admin route ("it can open the console");
- the deploy step "narrow the console from the admin".

The seeded data was correct. Every sentence about what it does was wrong.

## 1. Read the consumer's write path, per key

The fetch adapter answers **what arrives**; the writer answers **what wins**. Before writing any operator
text, rollback note or deploy step, open the code that writes the consumer's config and look for:
- **Preserved-if-present lists**: keys whose existing value survives a regeneration.
- **Explicit operator overrides**: a wizard, a CLI flag or a console form that outranks every source.
- **Merges in which the existing file beats the fetched values.**
- **Per-key special cases.** Access control, secrets and identity keys are the ones most often ranked apart,
  because the consumer's team did not want an upstream it does not control to change them.

Put a per-key precedence table in the plan: strongest → weakest, and **what a producer row actually
reaches**. Every refresh? Only a newly created file? Only a file that has no value yet? Treat the consumer's
own document as a hypothesis, like a spike's negative claim. Name the files you read, with the date or
revision, because a consumer that is mid-change can move under you.

When the consumer's source is outside the workspace, read it through the forge API. Say in the
verification record that the precedence was **read from source, not executed**.

## 2. Key transforms on the consumer side turn distinct rows into collisions

The producer may keep `TEMPLATE_X` and `template_x` apart, through a case-insensitive collation, no UNIQUE
key, and byte-exact seams. A consumer that lowercases or normalises names collapses them into one key, and
the one emitted **last** wins. The emission order is the engine's. In the field case, two runs on the same
data emitted the variant at different positions. Never present the order as a contract.

- **Before migrating:** run an inventory using the *consumer's* normalisation (`LOWER(name) IN (…)` for the
  new names), expect zero rows, and resolve any hit by hand. A migration must not delete operator data.
- **After operators edit:** run a duplicate check grouped by the normalised name. An admin "Add" without a
  uniqueness check creates a second row whose value may win over the one an operator then narrows.
- **In the walk:** record which variant the emitter returns last. That makes the collision observed, not
  argued.

## 3. Empty inherits, non-empty overrides — the seed is a decision

If the consumer reads "empty" as "use my default", a seeded non-empty value is an override, and it stops
following the consumer's template if that default ever changes. Seeding the consumer's stated default makes
the value explicit and visible in the admin, which is a common owner preference. Seeding empty keeps the
consumer authoritative. Let the owner pick, and write the consequence into the migration header either way.
(See [`EMPTY_IS_A_THIRD_STATE.md`](EMPTY_IS_A_THIRD_STATE.md) for the inherit-vs-none distinction.)

## 4. A seed that is inert today can go live tomorrow

When the consumer's writer outranks the producer for a key, a permissive seed (an allow-all `*`) does
nothing. When the consumer later aligns its code with its document, which is the obvious fix once someone
notices the mismatch, that same seed overrides every tenant's narrowed setting at the next refresh,
fleet-wide and without any producer change. **An empty seed is safe under both precedence models.**

If the owner keeps the permissive seed anyway:
- record the hazard in the migration header, in the row's operator text and in a hand-off note to the
  consumer's team ("clear these rows before letting the backend win for these keys");
- give the clearing step an owner and a moment that come before the consumer change ships, not after.

## 5. Every sentence about effect follows the writer

Rewrite the following to the real precedence:
- **The row's description:** "used only when the consumer writes a new file without its own value; after
  that the consumer keeps its own setting".
- **The rollback note:** deleting a row the consumer outranks reopens nothing.
- **The security notes:** what an unauthenticated writer of the table can really change.
- **The deploy step:** where an operator actually changes the setting, which may be the consumer's own
  console.

If the content-hashed migration carrying that text is already applied on a dev database, roll it back
there before editing, then re-run the walk.

## Checklist for the plan

- [ ] The consumer's **writer** is read, per key; the files and revision are named.
- [ ] A per-key precedence table, including what a producer row reaches.
- [ ] The consumer's key transforms (case, normalisation, last-wins) are named; there is a pre-migrate
      inventory and a post-edit duplicate check.
- [ ] The seed value (stated default or empty) is an owner decision, and its consequence is in the header.
- [ ] Any permissive seed the consumer outranks today is recorded as a hazard where the consumer's team will
      see it.
- [ ] Operator text, rollback notes, security notes and deploy steps are checked against the writer, not
      the document.
- [ ] The verification says which consumer behaviour was read and which was executed.

## Related

- [`SECOND_SOURCE_FOR_AN_OPS_ONLY_SETTING.md`](SECOND_SOURCE_FOR_AN_OPS_ONLY_SETTING.md) — precedence
  *inside* the producer; this file covers precedence inside the consumer.
- [`WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md`](WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md) — the
  emitter that makes every new row reach the consumer with zero code.
- [`CONTRACT_CONSUMER_DISCIPLINE.md`](CONTRACT_CONSUMER_DISCIPLINE.md) — the mirror case: building against
  a producer's contract.
- [`../../deployment/references/CONVERGENT_SEED_ROW_MIGRATION.md`](../../deployment/references/CONVERGENT_SEED_ROW_MIGRATION.md)
  — the seed-row migration shape itself.
- [`../../review-loop/references/LARGE_PR_INDEPENDENT_REVIEW.md`](../../review-loop/references/LARGE_PR_INDEPENDENT_REVIEW.md)
  — the independent pass that caught it; give it the consumer's repository to read.
