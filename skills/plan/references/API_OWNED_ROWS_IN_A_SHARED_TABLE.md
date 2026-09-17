# API-owned rows in a shared legacy table — an ownership flag, and one comparator per concept on both seams

Load when a plan gives an **API client a write path (create / update / delete) into a table other
writers already own** — an admin screen, seed scripts, application code that inserts as a side
effect — and the client must be able to manage *its own* rows without being able to damage the
rest. Typical shape: a key → value(s) lookup table on a legacy engine, addressed by a natural key,
with no usable unique constraint. Field-proven on a MySQL / PHP translation-strings table; nothing
in it is specific to that stack except the collation examples.

The design has five moving parts. Each one has an obvious version that reads true and runs false.

## 1. An ownership flag whose DEFAULT keeps every existing writer correct

Add a two-valued column (`owned TINYINT NOT NULL DEFAULT 0`), set it **only** in the API's
insert / adopt statements, and let update and delete touch **only** flagged rows.

- The **DEFAULT is load-bearing**: every legacy writer that names its columns (an admin save, a
  seed INSERT, an auto-logger) keeps producing non-API rows *without being touched*. Inventory those
  writers before choosing the default, and say in the migration header which ones rely on it.
- `NOT NULL`, so the ownership test is two-valued; no index if every read of it rides the key.
- **Un-migrated deployment**: name the column in the API's first SELECT, so the failure is one clean
  error before any write — and check that *nothing else* breaks (no `SELECT *` → `INSERT` round
  trip, no positional import). State the deploy order as a gate.
- **Rollback forgets ownership.** A down-migration drops the flag; after a re-apply every former
  API row is a foreign row the API refuses. Stamp created rows with a constant marker in an existing
  free-text column and put the recovery `UPDATE … WHERE <marker>` in the down-file's header — and
  say which rows it cannot recover (adopted ones, § 2).
- The flag will appear on every **wholesale emitter** of the table the moment it exists
  (`WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md`). Decide whether that is a leak or a feature — it
  may be the only read surface that tells the client which rows are its own.

## 2. Reads that write: the adopt-empty-stub carve-out

Ask who else inserts into the table, **including as a side effect of reading**. A "log the missing
key" path (a translate adapter, a settings registry that materialises defaults, a lazy
get-or-create) inserts an *empty* row for any key the application merely looks up. Under a strict
"refuse every row the API did not add" rule, such a stub **blocks that key for the API forever**,
and the client cannot delete it either.

Put the choice to the user with the real producer named. The workable rule: a foreign row is
refused **unless it is an untouched stub** (not flagged and every value column empty) — that one is
*adopted*: written like an update, flagged, owned from then on. Consequences to write down:

- "A stub is not deletable" and "a stub is adoptable" together make delete a two-call formality
  (adopt with a key-only item, then delete) — document it in the client contract so nobody gets
  stuck.
- After a delete, the side-effect writer may re-create the stub; a later save adopts it. The
  delete's read-back must therefore pass when a *non-owned* row carries the key.
- The side-effect writer's own existence check often uses the column collation (case-, accent-,
  padding-insensitive) while the API is exact: an API row `FOO` silently suppresses the stub for
  `foo`. Harmless, but it belongs in "known edges".

## 3. No UNIQUE key is possible → an all-or-none INSERT, then a read-back

Sniff the data before designing uniqueness: shared legacy tables usually **already contain
duplicate keys** (an admin form with no check, a racy auto-logger), so `ADD UNIQUE` fails on the
first deployment and an integrity-error catch (`UNIQUE_KEY_TWO_LAYER_WRITER.md`) has nothing to
catch. The guarantee moves into the statement:

```sql
INSERT INTO t (k, v1, v2, owned, …)
SELECT n.k, n.v1, n.v2, 1, … FROM (SELECT ? AS k, ? AS v1, NULL AS v2 UNION ALL SELECT ?, NULL, ? …) n
WHERE NOT EXISTS (SELECT 1 FROM t x WHERE <exact-key predicate over ALL new keys>)
```

The guard names **every** new key, so the statement inserts all rows or none — which is what makes
"all-or-nothing" true for the create half without a transaction. On a table-locking engine the
statement holds the write lock for its whole duration; on a row-locking engine it fails safe (the
read-back catches what slipped through). Probe it through the **real driver path** (prepared
statements): UNION typing with a short first row and a long later value, literal `NULL` columns,
connection-vs-column charset, and that `INSERT … SELECT` from the target table is legal on your
engine.

Then: **treat rows sharing a key as one unit** (all must qualify; the statement writes or deletes
them all; the read-back compares *every* row), **never read the affected-row count** (drivers
report rows *changed*; an identical re-send changes none), and order the phases so the most likely
race writes nothing — *create → read back → update → read back*. A read-back mismatch is a
"concurrent modification, re-send" error; design both actions **idempotent** so the re-send
converges, and say in the contract which interleaving converges to a refusal instead.

## 4. One comparator per concept, identical on both seams

Every predicate the design evaluates twice — once in application code to *authorize*, once in SQL
to *guard the write* — must use the same comparator on both sides, or the guard and the authorizer
disagree about which rows they are talking about. There are usually **three**, and the storage
disagrees with the application on all of them:

| Concept | Application | SQL trap | Portable form |
| --- | --- | --- | --- |
| **Key equality** | readers key a hash map: byte-exact, untrimmed, integer-like strings become ints | the column collation folds case, accents and trailing spaces | `k IN (…) AND BINARY k IN (…)` — the first half uses the index, the second makes it exact (a bare `BINARY k = ?` is a full scan); refuse keys the reader's map would mangle |
| **Emptiness** ("is this an untouched stub?") | `=== null \|\| === ''` | `COALESCE(c, '') = ''` is **true for `' '`** under a PAD SPACE collation; one expression over several columns (`CONCAT`, multi-column `IN`) **errors** when a single column has a different collation | per column `COALESCE(LENGTH(c), 0) = 0`, joined by `AND`; pin the forbidden forms negatively |
| **The flag itself** | the driver may return **native ints** (prepared statements) where fixtures use strings | — | compare `(int) $row['owned'] === 1`; feed unit tests *both* types, or a string-typed fixture keeps a guard green that refuses every real row |

Find the third column type by *fetching a row through the real adapter* at plan time, not by
reading the DDL. Find the collation outliers with `information_schema.COLUMNS` — one column with a
different collation than its siblings is enough to break every multi-column expression.

## 5. Refuse what the storage would silently corrupt

If the read-back is the success signal, anything the storage *changes on the way in* becomes an
error **after** a committed write. Find the silent transformations for this table — narrower column
charset than the connection (4-byte characters cut the value at that character), non-strict SQL mode
(over-long values truncated with a warning), type coercion — and refuse those inputs at parse time.
Check whether the application *disables* strict mode at connect: then truncation is a fleet fact,
not a dev-stack quirk.

## Make the orchestration executable

The ordering guarantees above ("no update after a failed create read-back", "no cache reload after
a refusal", "a failing reload keeps the success") are the riskiest logic and the least visible to a
source pin. Put the sequence in a pure function driven through a **small gateway interface** the
model implements (`getRowsByKeys`, `insertOwned`, `updateOwned`, `deleteOwned`) plus a side-effect
callable, and test it with a scripted fake — see `skills/work/references/EXECUTE_OVER_PIN.md`
§ Orchestration behind a gateway. A verification step that needs a patched build to reproduce a
race is the sign this was skipped.

## Checklist for the plan

- [ ] Every writer of the table inventoried, **including side-effect writers**; the DEFAULT argued
      against each.
- [ ] Data sniff: duplicates, key shapes (case pairs, padding, line breaks, integer-like), empty
      rows, column collations — on real data, not the DDL.
- [ ] Stub rule decided by the user with the producer named; delete-a-stub route documented.
- [ ] The three comparators written out for both seams; forbidden SQL forms pinned negatively.
- [ ] Statement shapes probed through prepared statements on a scratch copy; scratch dropped.
- [ ] Silent storage transformations listed and refused at parse time.
- [ ] Idempotency + the re-send story (incl. the interleaving that ends in a refusal) in the contract.
- [ ] Deploy gate, un-migrated blast radius, rollback recovery statement.
