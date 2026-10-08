# A reversible walk on a shared database: whole-schema `AUTO_INCREMENT` watermarks

Load when verification writes **through the application** to a development database that other stacks share,
and the write is narrow: one request, or one queued task processed by id. A private copy is overkill for that.
The application writes rows you cannot list in advance (queue rows, logs, price details, carts), and every one
of them must be gone afterwards. A batch drain that takes every pending row is a different case:
[`WALK_A_BATCH_DRAIN_ON_A_PRIVATE_COPY.md`](WALK_A_BATCH_DRAIN_ON_A_PRIVATE_COPY.md).

## 1. Watermark every table, delete what grew

- **Before the walk**, snapshot `information_schema.tables.auto_increment` for the whole schema. Run
  `SET SESSION information_schema_stats_expiry = 0` in the **same** session first. MySQL 8 otherwise answers
  InnoDB tables from a cached statistic, which can be stale by exactly your rows.
- **After the walk**, join the two snapshots and, for every table whose counter grew, delete rows at or above
  the saved value on its auto-increment column. Print the count per table. That printed list *is* the
  inventory of what the application wrote, and it is usually longer than you would have listed.
- **A non-transactional engine (MyISAM) keeps what was written before a crash.** Use that to read a
  half-finished effect, and remember it is not rolled back, so it must be in the delete too.

## 2. The delete takes everyone's rows: walk an idle database

The watermark delete cannot tell your rows from a concurrent writer's. Run the walk only while nothing else
writes: no primary stack in use and no cron. Say so in the script header and in the verification doc. If the
database cannot be quiet, walk on a private copy instead.

## 3. State that is not new rows

- **Rows you change with `UPDATE`** (a client's settings, a feature flag) have no watermark:
  - back up the exact bytes (`HEX(col)`) before the change;
  - restore them from an **EXIT trap**, so an interrupted run restores too;
  - compare `MD5(col)` with the starting value at the end.
- **Refuse to start** when the row still carries your probe's marker value. A re-run would otherwise back up
  the previous run's leftovers as "original", and the MD5 check would then pass against the wrong baseline.
- **Cache / queue keys** (Redis): record `DBSIZE` before and after and list the new keys. Some are the walk
  environment's own debris: a lock left because a dev-only crash skipped its release blocks the next call.
  Delete those, but only on an idle stack, since the key is shared. A request counter is acceptable residue;
  say so.

## 4. Shell traps that make the cleanup silently partial

- **`docker exec -i` inside `while read … done < file` eats the loop's stdin.** Only the first table is
  processed, with no error. Drop `-i` when the query goes through `-e`.
- **`join` needs input sorted under its own collation.** Run both `sort` and `join` under `LC_ALL=C`; with
  underscore-heavy table names, mismatched locales skip lines with no error.
- **bash 3.2 (macOS) with `set -u` treats an empty array as unbound.** Use `${a[@]+"${a[@]}"}`.
- **Prove the cleanup with a separate query** for the residual rows. One field run reported success after
  deleting from one of four grown tables.

## 5. Before and after on the same database

Run the same script, with the same fixtures, against the default-branch code first (a worktree stack at the
plan commit) and then against the fix. Compare row by row. Pick fixtures the *real* code path accepts: a
background worker may refuse a stay that has no price, where a request-level probe never asked. See
[`LIVE_BEFORE_ORACLE.md`](LIVE_BEFORE_ORACLE.md) for the two-stack form.

## Related

- [`WALK_A_BATCH_DRAIN_ON_A_PRIVATE_COPY.md`](WALK_A_BATCH_DRAIN_ON_A_PRIVATE_COPY.md)
- [`LIVE_BEFORE_ORACLE.md`](LIVE_BEFORE_ORACLE.md)
- [`MUTATION_PASS_DISCIPLINE.md`](MUTATION_PASS_DISCIPLINE.md): a check must be able to fail.
