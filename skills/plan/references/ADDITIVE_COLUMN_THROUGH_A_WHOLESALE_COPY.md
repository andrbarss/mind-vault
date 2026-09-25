# An additive column on a table whose rows are copied wholesale into another — destination first, the backfill is not a migration, a guard in a shared loader is loader-wide

Load when a plan adds a column to a table **and any writer builds an `INSERT` into a second table from a
`SELECT *` of the first** — a catalogue row snapshotted onto an order line, a template copied onto an
instance, a product copied onto a cart item, a profile copied onto a booking. The wholesale-*emitter* rule
([WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md](WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md)) says a
`SELECT *` reader publishes columns it never names; this is its write-side twin: a `SELECT *`-fed writer
*inserts* columns it never names, into a table that may not have them. Field case: one nullable column on
a catalogue table, requested as "one `ALTER` and one reader line", was four traps.

## 1. The copy path makes the destination's columns a dependency of the source's

`$row = $source->getRow($id); … ; $destination->insert($row);` — every column of the source row reaches
the `INSERT`. Add a column to the source alone and the next copy fails with *Unknown column* on the
destination. Field shape: every sale of a catalogue item, **and** every creation of a parent record that
auto-copies a mandatory item — where the parent row is persisted *before* the copy, so the failure leaves
a half-written parent, not a refused request.

- **Grep for the copy path before writing the DDL**: an `->insert($x)` / `INSERT … SELECT *` whose array
  came from a `fetchAll` / `getX()` of the source table. A symbol grep for the new column finds nothing —
  the copy names no column. Grep the *container* (the source table's loader) for its callers instead.
- **The destination gains the column first, in its own migration**; the source's migration depends on it.
  A destination column without a source column is harmless (every row reads NULL); the reverse is an
  outage. Look for the precedent — a column that already sits on both tables was added the same way.
- **Two migrations, ordered — not one file with two `ALTER`s** when the runner is non-transactional and
  its rule puts the single unguardable statement last: with two `ALTER`s in one file, the second failing
  leaves the first applied and unrecorded, and every retry hits *Duplicate column*. Two files make each
  `ALTER` the last statement of its own stem. Write the dependency into both headers (the source stem
  "requires" the destination stem; the destination stem's DOWN "never roll back while the source stem is
  applied"), and into the rollback story: revert the source stem first (`--migration=<stem>`) or both.
- **The scaffold may not enforce the order you need.** A `create` helper that stamps the stem to the
  second with a per-*slug* collision guard gives two `create` calls inside one second the same prefix,
  and the runner then sorts by slug — possibly the outage order. Scaffold a full second apart, list the
  order before writing any SQL, and pin the order in a DB-free test (`strcmp` on the full stems, plus
  the exact `ADD COLUMN` per table and the `DROP` per down-file). Then file the helper fix as its own
  idea: a stamp of `max(now, greatest prefix on disk + 1 s)`, which makes scaffold order the apply
  order. Once the scaffold is monotonic, scaffolding in apply order is enough, and the `strcmp` pin
  still guards the committed pair. Mechanics in
  [`ORDERED_SCAFFOLD_TIMESTAMPS.md`](ORDERED_SCAFFOLD_TIMESTAMPS.md).

## 2. Snapshot or join — and what NULL means on the copy

Once the column is on both tables, the copied value is a **snapshot** at copy time. Decide with the
owner whether readers of the destination show the snapshot (re-editing the source does not change
records already built — the behaviour of every other copied attribute) or join the live source value
at read time (always current, but the copy path must then strip the key, and every other wholesale
reader of the destination never sees it). State the answer in the contract's model section: NULL on
the destination is a meaningful, permanent value — every non-copied row type, and every copy made before
the source row was curated.

## 3. A backfill that runs before the source is populated copies nothing

"Snapshot plus backfill" is a common owner decision. A backfill stem `UPDATE dest JOIN src SET dest.col =
src.col WHERE dest.col IS NULL AND src.col IS NOT NULL` looks right and is a **no-op at migrate time**: the
source column is brand new and every value is NULL until operators curate it; a ledger-tracked migration
runs once and is recorded as done. The backfill is therefore an **operator's one-off**, documented in the
contract and the verification guide, idempotent, fleet-wide by construction — say so, and say who decides
per tenant whether to run it (it changes what returning customers see on records they already built).
Walk it once on the dev clone and record the affected-rows count: it touches every NULL copy of every
curated source row on the clone, not the handful the walk added; revert with `UPDATE dest SET col = NULL`
while the column is brand new, and never once real data exists.

## 4. "Endpoint-scoped" is a claim about callers, not about the method

The house pattern for adding a key without touching a shared producer is a guard at the *consumer's*
seam — a loop in the service that builds the endpoint's answer. When that seam is the service's
**reservation / order loader**, every reader the loader serves gets the key: the listing endpoint, the
active-cart endpoint, the lookup-by-code endpoint, the coupon-eligibility answer, the self-check-in and
account readers. A contract that says "only endpoint X adds the key; no other reader does" is then false
for every sibling, and a consumer coding the "key may be absent" branch against it builds a dead path.

- `grep -rn "<loaderMethod>("` before writing "endpoint-scoped" or any negative about other readers;
  name the reader set from the callers.
- The reader-side table of the contract gets two rows: readers built through the shared loader (key
  present on every tenant) and readers that bypass it (key present only once migrated).
- The wholesale readers of the *destination* table (`SELECT *` grids, exports) publish the column with
  no code and no guard — list them too.

## 5. The cleanup that follows a walk

A verification walk leaves untracked artefacts (a throwaway runner config, log files the stack wrote).
A cleanup script that removes `log/*` wholesale deletes **tracked placeholder logs** the repo ships;
`git status` shows them as `D`, `git checkout -- <paths>` restores them. Remove the walk's files by name,
gitignore the throwaway config directory the docs already describe as ignored, and never glob-delete
inside a directory that mixes tracked and untracked files.

## Plan checklist

- [ ] Every `INSERT` fed by a `SELECT *` of the source table is listed; each destination gets the column
      first, in its own migration, with the dependency in both headers and the rollback order stated.
- [ ] The migration order is enforced by construction (scaffold a second apart, list, pin with `strcmp`),
      not assumed from the scaffold.
- [ ] Snapshot vs join decided by the owner and written into the contract's model section, with what
      NULL means on the copy.
- [ ] A backfill whose source is populated after the migration is an operator statement with the
      affected-rows count from the walk, not a stem.
- [ ] Any "endpoint-scoped" / "no other reader" claim is derived from the guard's callers; the contract's
      reader table splits shared-loader readers from bypassing readers.
- [ ] The walk's teardown names its files; tracked placeholders survive.
