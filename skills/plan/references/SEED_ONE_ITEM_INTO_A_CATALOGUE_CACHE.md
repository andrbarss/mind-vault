# A check about one item that builds the whole catalogue: seed that one item, built exactly as the catalogue builds it

**Load when** a plan speeds up a request whose cost is a lazily filled **catalogue cache**: a model
method such as `getItem($id)` that, on an empty instance, runs `getItems()` with no arguments.
That call loads every visible row plus per-row enrichment queries, all to answer about **one** id.
Typical callers are a validator (`isValidConfig($id, …)`), a nights or price check, or anything
that reads one product, packet or plan through a getter written for listings.

**Field case.** A channel booking endpoint validated the requested package through such a getter.
On a fresh model instance that meant the whole active catalogue: 1 query, plus 2 enrichment
queries per package. On the dev clone this cost ~5 ms. In production it was 66–87 % of every
request: median 0.57 s, 10.5 s under load. Two sibling stages had the same shape, and each was
fixed the same way, one stage per change:
- a nights check that built the catalogue to read one package's minimum stay;
- the package validator that built it to check guests, food and nights.

Production median for the stage went from 0.566 to 0.011 s. The parity oracle compared 236,160
validator answers against the default branch, and all were byte-identical.

## 1. Build the one item with the catalogue's own code, not a lookalike

The tempting fix is a new single-row query that fetches "the same fields". It drifts at once,
because the catalogue entry is rarely the raw row:
- language overrides copied over the base columns, plus a snapshot of the base;
- per-row enrichment (categories, flags read from config);
- columns that only exist after a migration, behind a presence guard.

Instead:

- **Extract the catalogue's per-row body verbatim** into `buildEntry(array $row, …)`. The listing
  loop calls it for every row; the new loader calls it for one. Compare the moved lines with the
  default branch's loop body, whitespace-normalised. That diff must be empty.
- **Share the selection.** The single-row read uses the **same predicate builder** the listing uses
  (`active = 1`, the visibility window, the channel filter). Reuse it rather than retyping the
  `WHERE`.
  - Check which arguments the listing call on this path actually passes. Here the getter called
    `getItems()` with **no** arguments, so there was no language clause.
  - A `$lng = null` default on the single-row reader has to mean exactly that no-argument selection.
- **Move reads that ran once per call** (the config flag, the enrichment models) into small
  helpers. Call them at the same point in both paths, so construction order and side effects do
  not change.

## 2. Seed the caller's own instance, and only an empty one

The loader fills `$this->items = [$id => buildEntry($row)]` and nothing else:

- **Only on an empty instance.** If anything already filled the cache, leave it alone. A partial
  cache must never shadow a full one.
- **Only from the hot caller**, on the instance it just created. Keep it an explicit call, not a
  flag inside the getter:
  - every other caller (the listings, the other validators, cron jobs that read the catalogue's
    ids) keeps the old path by construction;
  - a grep for the loader finds the one call site.
- **A miss seeds nothing.** An absent or invisible item leaves the cache empty, so the getter falls
  back to the catalogue exactly as before. The error answer stays the same, including the cases
  where the catalogue's key lookup misses a raw id that `intval` would hit:
  - `'028'`, `' 28'`, `'28abc'` as strings;
  - an array instead of a scalar (it throws the same `TypeError`).
- **A partial cache answers null for every other id.** That is the hazard. Before relying on it,
  list every `$this->` call the validator makes on the seeded instance and confirm that each one
  reads the requested id only. Pin that list in a test, so a later edit that reads a second item
  fails loudly.

## 3. The secondary-loader stub trap

Validators often warm a second per-item cache, such as `getItemRooms($id)`, that **writes an
entry into the same array** when it runs after a miss. It writes a rooms-only stub. The next
`getItem($id)` then finds a non-empty entry and validates against it: "not found" becomes a run
of guest-range messages. The fix:
- warm the secondary loader **only when** `getItem($id) !== null`;
- pin the order;
- keep a positive-control test that reproduces the stub on purpose.

## 4. What proves it

- **An executed test, not only a source pin.** Run the warm-up on a fresh instance with a mocked
  adapter and assert:
  - exactly one `fetchRow` with the expected SQL;
  - `never()` the catalogue query;
  - for the invisible and absent cases, `null` left behind;
  - for a raw-id spelling the catalogue misses, null.
- **A parity oracle against the default branch's checkout**, for:
  - every item × locale × raw-id spelling;
  - the validator's whole input space, each combination on a snapshot of the warmed cache restored
    before every call;
  - the full catalogue in each argument form other callers use.

  The method and its traps are in
  [`../../work/references/LIVE_BEFORE_ORACLE.md`](../../work/references/LIVE_BEFORE_ORACLE.md)
  § The in-process variant.
- **Mutations that must differ:**
  - the loader without the active filter;
  - the loader without the visibility window;
  - the entry builder missing one line.
- **Query count for the stage**, before and after: `2 + 2N` → `4` here.

## 5. Record what still builds the catalogue

The same getter usually has other hot callers: a second booking path, a reservation model's own
validator, a cron job that only reads ids. Name each one in the write-up as "unchanged, still
builds the catalogue". Each is a follow-up with its own oracle if its timing shows the cost.
Extending the loader to them is not a free rider, because each has its own instance lifetime.

## Related

- [`PRODUCER_ARGUMENT_CONTRACTS.md`](PRODUCER_ARGUMENT_CONTRACTS.md): which arguments the shared
  producer is called with on this path decides the selection the single row must match.
- [`../../work/references/HOT_PATH_MEASURE_THEN_SPLIT.md`](../../work/references/HOT_PATH_MEASURE_THEN_SPLIT.md):
  finding the stage in the first place, including when only production shows it.
- [`../../work/references/MUTATION_PASS_DISCIPLINE.md`](../../work/references/MUTATION_PASS_DISCIPLINE.md)
