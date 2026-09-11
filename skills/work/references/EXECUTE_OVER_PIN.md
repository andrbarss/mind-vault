# Execute over pin — a source-level pin proves text, not behaviour

Load when a `/work` step **amends a method the DB-free suite cannot construct** (an ORM /
table-gateway model, a framework controller, anything whose constructor needs a live adapter)
and the plan's coverage for that amendment is a **source-level pin** — a test that reads the
method's own source through reflection and asserts strings, order, or absence.

## When a pin is the right tool — and when it is a substitute

A pin is exactly right for invariants that *live in source shape*: a guard's absence, the
exception class caught, a status code set, call order, a column in a SELECT. It is the wrong
tool for **an extraction or refactor of a method that sits on a write path**: the pin proves
the messages are still *present* and *gated on the right key*; it cannot prove that a given
input still yields the same `messages` array. The user's question that surfaced this — "you
changed a critical method, have you written tests for it?" — had the honest answer *"only
pins"*, and that is a coverage gap disguised as coverage.

The tell in a `/work` report: the test list says "source pins on `<method>`" for a method that
was **changed**, not merely guarded. Ask: *does any test call it?*

## The recipe — bypass the constructor, seed the collaborators

Most "needs a DB" methods need it only through a few collaborators that are cache-backed or
pure. Construct the object without its constructor, seed the cache the collaborators read, and
call the method for real:

```php
// PHP — a Zend_Db_Table / Doctrine / Eloquent-style model whose constructor needs an adapter
$class  = new ReflectionClass('DbPackets');
$model  = $class->newInstanceWithoutConstructor();
$model->packets = array(11 => $row + array('rooms' => $rels));   // the cache getPacket()/getPacket_RoomsTypes() read
$result = $model->isValidPacketConfig(11, 5, $adults, $children, $teens, $infants, 'NONE');
$this->assertSame(array('status' => false, 'messages' => array('Incorrect number of adults: minimum 1 maximum 3')), $result);
```

```python
# Python — the same move
obj = Model.__new__(Model)          # no __init__, no session
obj._cache = {11: row}
assert obj.validate(11, adults=4) == ["Incorrect number of adults: minimum 1 maximum 3"]
```

Before writing it, **trace every branch the inputs will exercise** and confirm none reaches
the adapter / registry / network: read each collaborator the method calls and find the
cache-hit path (`if (isset($this->cache[$id])) return …` *before* the query). Pick inputs that
keep the un-seedable branches dead (a valid relation id so the "unknown relation" branch and
its translated message never run — unless the translation helper degrades gracefully without
its registry, in which case pin that branch too: the **full message order** is the part of
"byte-identical" no source pin can see).

Two details that make the executed test *discriminating* rather than decorative:

- **Use inputs that separate the semantics you claim.** `'4' > '3'` is true under both numeric
  and byte-wise comparison; only `'10'` (which is `< '3'` as a string) proves the comparison
  stayed numeric. A boundary-inclusive claim needs the exact min and max values, not one inside
  the range.
- **Cross-check the executed method against the extracted predicate dimension for dimension**
  (a dimension is in the messages iff the predicate names it) — that pins the *wiring*, which
  is the thing the refactor could have broken.

Keep the pin as well. The two are complementary: the pin guards the shape a later "harmonise
with the siblings" edit would erase; the executed test guards the behaviour.

## The live corollary

When a real environment is reachable, send **one** request down the amended write path with an
input that fails at the amended check — the validator answers before any side effect, so the
probe is safe even where the full write cannot complete — and record the byte-identical
message plus "0 rows written". It costs a minute and turns "the test says so" into "the
system says so".

**Walk every branch of a moved method.** When the amendment is an *extraction* of a
compute-and-write method (its head moved into a pure quote, the legacy tail still writing), a
before / after walk proves the move only for the branches it reached. List the method's write
branches (applies a discount / drops it / price unchanged — whatever its `if` ladder is) and walk
**each**, above all the branch that writes the most columns; read which branch a capture reached
from what it wrote. A capture showing "discount 0, message empty, free-text column untouched"
reached the no-discount branch, whatever the plan asked for — report it as that branch, not as
"the regression walk". Field case: the first walk was reported green, and the branch that rewrites
the free-text column was walked only after a review read the capture.

## Doubles and pins that discriminate

- **Make a double's two sources disagree.** When the code under test overrides a value a
  collaborator also computes (a pre-check's verdict replacing the collaborator's own), a double that
  returns the *same* value from both is green with or without the override. Seed them to disagree —
  pre-check true / collaborator false, and the reverse — so only the override line produces the
  asserted result.
- **Quote the way the real adapter does.** A recording adapter double that quotes ints (`id = '42'`)
  where the driver leaves them bare pins text production never emits; copy the driver's quoting
  rules for the types the code passes.
- **Pin a guarded block as one contiguous, whitespace-normalised string**, plus
  `substr_count(call) === 1` for each side-effecting call. "Each write call appears after
  `if (!$dryRun) {`" still passes when a call moves below the block's closing brace or the guard's
  condition changes — a positional pin checks order, not containment. Where the method's exact
  statements *are* the contract (a post-commit method whose side effects each sit in their own
  `try`), `assertSame` the whole normalised method: brittle on purpose.

## Related

- `agents/AGENT_test-engineer.md` PASS 2 — the reviewer-side bullet that points here.
- Project-local pin recipes (whitespace-normalise before pinning SQL, strip comments before a
  negative assertion, `require_once` dispatcher-loaded classes) belong in the project's own
  solution docs; this file is the cross-project rule about *when a pin is not enough*.
