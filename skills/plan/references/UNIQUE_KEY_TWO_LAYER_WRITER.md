# Unique-key writer contract — normalise, validate, pre-check, catch the key

Load when a plan adds an **application-written column with a UNIQUE constraint** (a slug, a short
code, an external id, a handle) whose collisions must surface as a friendly field error and never as a
500. The DB enforces the key; the *experience* of a collision belongs to the writer, and the two
disagree about case, whitespace, timing and error type unless the writer is designed against the
key's real comparator and error surface. Field-proven on a MySQL/PHP admin API; the shape transfers
to Django (`IntegrityError` + `UniqueConstraint`) unchanged.

## The pipeline — order is the contract

1. **Normalise** (trim; empty ⇒ NULL; canonical case) — **only for the types the normaliser
   accepts**. A normaliser that runs before validation sees unvalidated input: an array from
   `field[]=x`, a JSON object, a number. Guard on type (`is_string` / `isinstance`) and pass anything
   else through raw so the validator's type rule answers 400. Moving normalisation ahead of the
   validator is a contract change — list every type the raw request can carry and write the
   hostile-type tests *before* the reorder.
2. **Validate** the normalised payload (nullable ⇒ short-circuit; format regex with the length bound
   inside it). Pin the format message as a constant the tests assert; map the *type* rule to the
   same message so the contract has one text per cause.
3. **Pre-check for the message**: `SELECT id, label FROM t WHERE col = ? AND id <> ?` (exclude self
   on update, no scope narrower than the key's namespace). Its only job is the friendly
   *"already used by <label> (id N)"* text. **Do not lock it** — a plain read in a transaction
   serialises nothing, and `FOR UPDATE` on a *non-existent* unique value takes a gap lock that
   deadlocks concurrent inserts. The transaction around create is for uniform exception handling,
   not atomicity.
4. **Catch the key for the guarantee**: the integrity error from the INSERT/UPDATE, discriminated on
   the **driver errno** (MySQL 1062 lives in `errorInfo[1]`; `getCode()` is the SQLSTATE `'23000'`),
   mapped to the *same* field error, re-running the pre-check to name the winner and falling back to
   *"already used by another record"* if the winner vanished. **Errno only** — testing the key name
   in the message is a regression vector: on a table with one unique key, a failed substring match
   drops a genuine duplicate into the generic error envelope, which is the 500-class outcome the
   contract forbids. Log the key name; never condition on it.

## The comparator — let the collation fold, let the writer store the canonical form

The key compares under the **column collation**, not under the writer's idea of equality. A
`*_unicode_ci` collation folds case, accents (`wífi` = `wifi`), trailing PAD space and `ß` = `ss`.
Store the canonical form (lower-case), and write the pre-check as `WHERE col = ?` with **no**
`LOWER()` / `BINARY` / `COLLATE` override — the pre-check and the key must use the *same* comparator,
so a legacy accented value blocks a new ASCII code in both layers and is named by the pre-check.
Probe it live at plan time (`SELECT 'wífi' = 'wifi'` under the table collation) and pin collation +
a live duplicate-key probe in the schema drift guard.

## The exception — pick a base no sibling catch already handles

A dedicated conflict exception is right (it carries code / winner id / winner label). Its **base
class** is a hazard: if it extends the class a neighbouring `catch` in the same action already maps
to a *different* field (`InvalidArgumentException → errors.other_field`), every duplicate is
reported as that other field's error — each catch reads as locally correct, only the order is wrong.
Extend a base nothing else catches (`\RuntimeException`) and **pin the full catch order in the plan**:
conflict → sibling domain exceptions → integrity/query exception → catch-all.

## Checklist for the plan's decisions section

- [ ] Normaliser type-guarded; hostile-type cases in the test list.
- [ ] Validator input named explicitly (raw request vs normalised payload) and the reorder's
      behaviour-preservation argued (presence semantics of `has()` / `sometimes`).
- [ ] Pre-check SQL written out, unscoped to the key's real namespace, no lock.
- [ ] Integrity-error discrimination: errno location for *this* driver, errno-only condition.
- [ ] Message strings as constants; the tests assert the constants.
- [ ] Conflict exception base class + full catch order pinned.
- [ ] Collation probed; drift guard asserts collation + live duplicate.
- [ ] If the column is rolled out per tenant: every **client-named** read surface (sort, filter,
      live-search field lists, export columns) strips the column when absent — see the architect's
      PASS 4 additive-column bullets.
