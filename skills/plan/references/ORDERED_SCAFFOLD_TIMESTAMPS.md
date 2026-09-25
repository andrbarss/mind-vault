# Ordered scaffold timestamps — a later scaffold must sort after every earlier one

Load when a plan touches a helper that stamps generated artifacts with a timestamp prefix whose
**lexical order is the apply order**, such as migration stems (`<YYYYMMDDHHMMSS>_<slug>`), numbered
seeds, or ordered patch files. It also applies when a plan has to scaffold two such artifacts whose
order matters.

## The trap

A stamp of `now` plus a guard that only refuses an **identical path** looks collision-proof, but it
isn't. Two scaffolds inside one second share the prefix, and the runner breaks the tie on the rest
of the name, usually the slug. The author ran `create b` then `create a`, and the runner applies `a`
first. Nothing fails at scaffold time. The wrong order only shows up when the second artifact
depends on the first, for example a column added to a snapshot table before the catalogue column
that a wholesale copy then carries across.

The same thing happens without any burst:
- a stem another branch dated a few seconds ahead (clock skew, or a hand-typed prefix);
- a local clock that repeats an hour at the DST fall-back.

## The fix: a monotonic stamp, derived from the directory

`prefix = max(now, greatest prefix on disk + 1 unit)`

- **Scan every file that owns a prefix.** That means up- *and* down-files: an orphan down-file still
  occupies its prefix. Ignore the index / README and anything that doesn't match the full
  `<digits>_<slug>.<kind>` shape.
- **Keep the directory as the only state.** Don't add a counter file or a table. A counter file
  conflicts on every merge and can drift from the files it describes; the names can't disagree with
  themselves. The limit is visibility: only the current checkout is scanned, so ordering across
  unmerged branches is unchanged. Say that in the docs, not just in the code.
- **Do the `+1` in calendar arithmetic, never integer arithmetic.** `…142559 + 1` must give `…142600`,
  not `…142560`, and the year must roll over. Do it in a zone without DST gaps (UTC), treating the
  prefix as a naive label.
- **Validate with a round trip, not a `false` return.** Some date parsers *normalise* an impossible
  value instead of rejecting it. PHP's `DateTimeImmutable::createFromFormat('!YmdHis', …)` turns
  `…142560` into `…142600` and `20261340…` into the next February. The validity test is
  `format(parse(s)) === s`. Probe the parser you actually use before you trust it.
- **Parse only a prefix that can win.** For fixed-width digit prefixes, string order equals numeric
  order, so compare as strings first. If the greatest prefix is below `now`, return `now` without
  parsing it. A malformed stem from last year must not block every future scaffold. Throw only when
  the malformed prefix would decide the result.
- **Announce the bump; don't refuse it.** Print one line naming the stem that forced it (for example
  `Timestamp bumped: <now> -> <ts> (sorts after <stem>)`). A far-future typo then shows up on the
  next scaffold. Refusing instead would block every scaffold on the checkout until someone renames a
  stem that may already be applied and checksummed. Whether to *warn* past some horizon is an owner
  decision; ask.
- **Keep the exact-path guard, and describe it accurately.** Once the stamp is monotonic, a file on
  disk before the scan is bumped past and can't collide. The only case left is a same-slug race
  between two processes, in the gap between the scan and the check. Two concurrent scaffolds with
  *different* slugs still share a prefix; write that down instead of claiming the guard covers it.
- **Watch for a language's key coercion.** In PHP, numeric-string array keys become integers. A
  `prefix => stem` map returns `int` keys, so cast back before any `strcmp`, and type the docblock as
  `array<int|string, string>`.

## Tests that discriminate

Each of these fails for one specific wrong design:

| Case | Catches |
| --- | --- |
| Three scaffolds with the same `now` → strictly increasing | a guard with no bump |
| `…59` → `…00` of the next minute; `YYYY1231235959` → next year | integer `+1` |
| an existing prefix *after* `now` → that prefix + 1 | a "loop while the same prefix is taken" design |
| a malformed prefix below `now` → `now` | parse-always |
| a malformed prefix that would win → throws | a silent normaliser |
| a temp-dir scan with an orphan down-file, a README and an unprefixed name | a scan that reads up-files only |

If the scan relies on the filesystem listing being sorted (a sorted `glob()`), don't add a
tie-break the listing already guarantees. No test can reach it, and a reviewer will ask why it's
there.

## The workaround for an unfixed helper

When the helper is still per-slug:
1. Scaffold the dependent artifacts at least a second apart, in apply order.
2. List the order before writing any content.
3. Pin it in a DB-free test with `strcmp` on the full stems.

Keep that pin after the helper is fixed. It still guards the committed pair against a rename.

## Related

- [`ADDITIVE_COLUMN_THROUGH_A_WHOLESALE_COPY.md`](ADDITIVE_COLUMN_THROUGH_A_WHOLESALE_COPY.md) — the two-stem case where the order is load-bearing.
- [`../../work/references/MUTATION_PASS_DISCIPLINE.md`](../../work/references/MUTATION_PASS_DISCIPLINE.md) § A smoke must be able to fail — how to prove the bump on the real command.
