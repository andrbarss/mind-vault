# Migration statement ordering on non-transactional runners — idempotent first, unguardable last (up-file AND down-file, independently)

Load when authoring or reviewing a multi-statement SQL migration for a runner without transactional DDL — MySQL (DDL auto-commits regardless of engine; MyISAM has no transactions at all), or any home-grown runner that streams statements (`multi_query`-style, aborting mid-file) and records its applied-ledger row only after the whole file succeeds.

## The failure topology

With a non-transactional runner + full-file-success ledger, a mid-file failure leaves **partial state with no ledger record** — so the retry replays the file **from the top**. Whether that retry converges or wedges depends entirely on statement order:

| Order | Failure point | Retry outcome |
| --- | --- | --- |
| unguardable `ALTER` first, guarded `INSERT` last | ALTER ok → INSERT fails | retry replays the ALTER → `Duplicate column name` → **that DB is permanently stuck** mid-migration, manual surgery required |
| guarded `INSERT` first, unguardable `ALTER` last | INSERT fails | clean retry (nothing happened) |
| guarded `INSERT` first, unguardable `ALTER` last | INSERT ok → ALTER fails | retry: INSERT no-ops via its guard, ALTER retried — **converges** |

On a one-DB-per-tenant fleet this isn't hypothetical: one wedged tenant DB blocks the whole fan-out's exit-0 and needs per-DB hand-repair.

## The rule

**Within one migration file, order all idempotent statements BEFORE the single non-idempotent one.**

- *Idempotent*: `CREATE TABLE IF NOT EXISTS`, `INSERT … SELECT … WHERE NOT EXISTS`, `UPDATE`, `DELETE`, `DROP TABLE IF EXISTS`.
- *Non-idempotent / unguardable*: `ADD COLUMN`, `DROP COLUMN`, `ADD INDEX` — MySQL (unlike MariaDB) has **no `IF [NOT] EXISTS` for column DDL**, so these cannot be guarded in-file.
- Keep **at most one** non-idempotent statement per migration file. Two unguardable statements in one file (e.g. `ADD COLUMN` + `ADD INDEX`) leave an unavoidable wedge window between them — split into two migrations if the runner's granularity allows, or accept and document the window.

## The down-file is NOT a mirror — apply the rule independently

The trap: "reverse the up-file" reads as "mirror the statement order". But the rollback runner has the **same** failure topology (streamed statements, ledger row deleted only on full-file success), so the down-file needs the same rule applied **on its own statements** — which usually produces an order that is *not* the mirror of the up-file:

```sql
-- up: guarded INSERT (idempotent) ...... first
--     ADD COLUMN (unguardable) ......... last

-- down, WRONG (mirror): DROP COLUMN first → a following DELETE fails →
--   ledger still says applied → every rollback retry replays the DROP →
--   permanent "Can't DROP <col>" wedge.

-- down, RIGHT (rule re-applied):
DELETE FROM `settings_table` WHERE `key` = '<seeded-key>';   -- idempotent first (0 rows on retry = fine)
ALTER TABLE `main_table` DROP COLUMN `<col>`;                -- unguardable last
```

Write the down-file's header comment to say so explicitly ("same retry-convergence rule as the up-file, NOT a strict mirror") — otherwise the next author "fixes" it back to a mirror.

## Review checklist for a multi-statement migration pair

1. Identify each statement as idempotent vs unguardable — in **both** files.
2. Exactly one unguardable statement per file? If more, can it split?
3. Unguardable statement last in the up-file **and** last in the down-file?
4. For every failure point in both files, walk the retry: does it converge?
5. Does the project's migration-convention doc state the rule? If not, add it there in the same PR — the migration that taught the lesson is the right vehicle (this is how the rule stops being tribal knowledge).

Provenance: an architect review caught the up-file ordering; the down-file's independent (non-mirror) application was caught only by a second reviewer pass after the up-file rule was already codified — the mirror intuition survives the first lesson, which is why this reference spells out the down-file case.
