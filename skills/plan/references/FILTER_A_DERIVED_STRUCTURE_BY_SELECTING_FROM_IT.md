# Filter a derived structure by selecting from it — never by deriving it a second time

Load when a plan adds a **filter, search or "only mine" view** to an endpoint whose answer is a
*derived* structure: a cached lookup map, a merged catalogue, a fold over several sources, a
computed index. The tempting design is a second, narrower derivation ("just add a `WHERE`"). It is
almost always wrong, and the reason is visible only when you read how the unfiltered answer is built.

## The shape of the problem

The unfiltered endpoint returns a key → value map. Building it is a fold: a remote default
catalogue first, then every row of a table in a particular order, the last non-empty value winning,
an "empty" value (NULL, `''`, *and* `'0'`) falling back to the key or to the default, duplicates
collapsing, the result cached per node for a day. The request is "return only the entries that
carry flag X" — and the flag lives on the table rows, not in the map.

A SQL-side derivation (`SELECT key, value … WHERE flag = 1`) gets every one of those rules to
re-implement: the fallback, the duplicate winner, the `'0'`-is-empty quirk, the column whose
collation differs from its siblings, the entries that have no row at all. It drifts on the first
edge, and the client now sees **two different values for the same key** depending on whether it
filtered.

## The pattern

**Call the same producer the unfiltered path calls, then remove entries.**

- The filtered answer is a **subset of the unfiltered answer by construction** — same keys, same
  values, same staleness. State it as a requirement (the *subset invariant*) and test it: for every
  entry of a filtered answer, the unfiltered answer holds the same key with the same value.
- What the filter needs from storage shrinks to a **membership list**: the keys that carry the
  flag. One narrow statement, no comparison on the value columns, nothing collation-bound.
- A filter on the *key itself* (prefix, namespace) needs no storage at all — match it in code
  against the keys the map publishes. This also removes `LIKE` escaping (`_` and `%` are ordinary
  characters in real keys far more often than one expects — sniff the data) and the question of
  which collation compares.
- **The component everyone depends on stays untouched.** A cached translator / catalogue / settings
  adapter serves every page; changing its cache shape to carry one more attribute is a blast radius
  the feature does not need.

### Complement semantics — decide it, and make it a partition

If the flag has two values, decide what the *other* value returns **for entries that have no row**
(defaults merged in from elsewhere). Two honest options:

- *complement* — everything the first value does not return. `0` and `1` partition the unfiltered
  answer exactly; only the (small) positive membership list is ever read. Usually right.
- *rows only* — entries backed by a row with the other value; entries without a row appear under
  neither. Literal, but `0 ∪ 1 ≠ all`, and the membership list is the large one.

Whichever is chosen, write the partition (or its absence) into the contract and pin it in a test.
It is a user decision, not an implementation detail.

## The trap inside the pattern: the published structure is not the fold you read

Selecting from the producer's output means matching **its keys** against storage keys — and the
output may have been through a transform *after* the fold. Field case: the adapter built a map
keyed by the stored string, then handed it to a generic merge helper that **renumbers integer
keys**; every integer-like stored key (`"12"`) reached consumers as `0`, `1`, … in fold order. The
stored key was gone before any consumer saw the map, the fold's own documentation was accurate,
and the plan's author had read the fold carefully.

Consequences to design for:

- **An entry whose key did not survive is never matched against storage.** Here: an integer map key
  short-circuits to "not owned". Without that rule, a row whose stored key is `"2"` claims whatever
  unrelated entry happens to sit at position 2 — a silent misattribution no subset test catches
  (the entry *is* in the unfiltered answer; it is just not that row's).
- **A key filter matches the key as published**, and the contract says so.
- **Fixtures go through the producer's own transform.** Build the test map by passing a fold-shaped
  array through the same call the producer uses; a hand-written "integer key 12" asserts a shape
  production cannot emit, and the test is green on a rule that never fires.
- **Trace to the emitter, not to the fold.** Before locking the design, follow the structure from
  the function that builds it to the function that *returns it to your caller*, and look for
  merges, re-indexing, sorting, serialisation. One `php -r` / REPL line on the real runtime
  settles a suspected transform; reading does not. (Sibling of
  `VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md`.)

## Other details that bit

- **Storage values are not keys until you say so.** A membership list read with a column fetch
  contains duplicates, possibly `NULL`, possibly non-strings. Build the lookup from strings only —
  in a language whose arrays coerce keys, `null` aliases the empty-string key.
- **Encoding parity.** If the filtered path encodes the result itself, it must produce the same
  bytes as the unfiltered encoder for the same entries — *except* where a shape change is forced
  (a result whose keys are exactly `0..n-1` would serialise as a list, not an object). Diverge only
  there: a blanket "cast to object" is not byte-neutral (JSON encoders may drop object properties
  with unusual names that the array form keeps). An unencodable body is an error status, never an
  empty success.
- **Staleness is asymmetric once the list is fresh and the map is cached.** After a write that did
  not reload the cache (or went through another node): a *created* key is in the list but not the
  map — it appears in **no** answer; a *deleted* key is in the map but not the list — it appears
  unfiltered **and under the complement**. Both directions go into the contract; the second is the
  one reviewers miss. A client that writes then reads back meets the first one immediately.
- **The refused request reads nothing; the key-only filter issues no statement.** Make the
  orchestration a pure function over two loaders (map, membership list) so "no loader called on a
  refusal", "membership list not read for a key filter", "loader throws → error status, text in the
  log only" are executable tests rather than source pins.

## Verification — independent derivation, not sibling parity

- Flag filter: derive the expected key set **from storage** (`SELECT DISTINCT <exact key> … WHERE
  flag = 1`) intersected with the keys of the unfiltered capture; compare with the filtered answer.
- Key filter: derive the expected subset from the **unfiltered capture** with a JSON tool
  (`startswith`), sort both sides, compare bytes.
- Partition: union equals the unfiltered answer *including values*; intersection empty; repeat
  under a key filter.
- Identity of the untouched path: hash the unfiltered body before and after the change, same cache
  state.
- If the dev data cannot show a trap (no key with the wildcard character followed by a
  non-separator, no case variant), say so in the verification note and cover it with unit rows —
  do not imply the walk proved it.
- Counts quoted in the plan from a quick sniff are *differently defined* from counts the walk
  produces (rows vs distinct keys, collation-grouped vs byte-exact). Reconcile them in the
  verification note or a docs reviewer will.

## Plan checklist

- [ ] The filtered path calls the same producer as the unfiltered path; the subset invariant is a
      numbered requirement with a test.
- [ ] The producer's output was traced to the point it reaches the caller; any post-fold transform
      is named, and keys that do not survive it are excluded from storage matching.
- [ ] Complement semantics decided by the user; partition pinned.
- [ ] Membership list: one statement, strings only, read lazily.
- [ ] Key filters matched in code against published keys; no `LIKE`.
- [ ] Encoder parity pinned on a fixture with awkward keys; unencodable → error status.
- [ ] Both staleness directions in the contract.
- [ ] Verification derives expectations independently (storage, capture), never from the filter.
