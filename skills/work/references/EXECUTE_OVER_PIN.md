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

## A forwarded argument needs a fixture where the wrong source answers differently

An extracted method takes a `$timestamp` (or an id, a locale, a tenant key) and forwards it to a
gate. Every executed test passes fixtures whose rows make the gate indifferent to the value — rows
with no time window, a single tenant — so the argument is *forwarded* but never *discriminated*: swap
the forwarding for `time()` (or the request's value for the process default) and the whole suite
stays green. Reviewers find this by asking, per forwarded argument, "which test goes red if the
callee reads the ambient source instead?"; if none, add one whose fixture pins the ambient source and
the argument to opposite answers — a window that closed a year before the given timestamp, refused
at that timestamp and accepted at the fixture's own instant. Mutation-test it once by hand (make
the swap, run the class, watch exactly that test fail) before trusting it. Such a test ages: the
ambient-clock branch flips when the calendar passes the fixture's window, so put the window far
out and say so in the docblock.

## A pin can lock in a wrong belief about a library — execute the library

A source pin asserts that the text you wrote is still there. When the text encodes a *belief about
a dependency*, the pin certifies the belief, right or wrong. Field case: "follow one redirect" was
written as an HTTP client's `maxredirects => 1`, pinned as that literal, and walked green on a
stack that never redirects. The client's loop is `++$count; … while ($count < $max)` — the option
counts **requests**, so `1` returns the first 301 unfollowed; every configured peer URL in
production was `http://` behind an https redirect, and the call swallowed its failures. The pin
made the bug a requirement.

- For any value handed to a library whose meaning you *inferred from its name* — a retry count, a
  redirect limit, a timeout unit, an inclusive / exclusive bound, a "depth" — write one executed
  test against the library's own test double (an HTTP test adapter with a scripted `301 → 200`),
  asserting the *outcome*.
- Add the **positive control of the quirk**: the same script with the intuitive value, asserting
  the wrong outcome. It documents why the constant is what it is, and fails loudly if an upgrade
  changes the semantics.
- Ask of every walk row: *could this environment have produced the failing input at all?* A dev
  stack with no TLS never redirects, a single-node queue never redelivers, a fresh schema has no
  legacy rows. Rows that cannot fail are not evidence; say so next to them and cover the branch in
  the suite.

## A second environment cloned from the first hides every cross-environment lookup

Verifying code that reads across tenants / schemas / services ("resolve this id in the *owning*
project's tables") needs a second environment, and the cheap way to get one is to copy the first.
Then every id exists in both with the same meaning, and a lookup in the **wrong** environment
returns the right-looking answer — the walk is green on the bug. An inner join against the wrong
schema is worse: it is an *existence* filter, invisible while both sides hold the id and a silent
row drop the day they differ.

- **Mark the copy**: prefix the human-readable columns of every catalogue the code resolves
  (`B:<name>`), so a wrong-environment read is visible in the payload.
- **Add ids the other side lacks** (a row above the original's max id) and route at least one
  fixture through them — the only way an existence-filtering join shows itself.
- **Use fresh identifiers for the environments themselves.** Copied data already carries the old
  environment ids; reuse them and pre-existing rows masquerade as the peer's.
- **Run the probe before the fix and keep the failing capture.** "Named by the wrong project's
  row; the peer-only record lost its link" next to the passing capture is what makes the row
  evidence.
- Mind the topology you built: if production's busy node is the *secondary* and your stack made
  the original the primary, one row must drive the flow from the secondary side — its resolution
  path is a different branch.

## Orchestration behind a gateway — ordering guarantees become unit tests

The extreme case of "a pin proves text": a controller action whose *sequence* is the contract —
validate → read → authorize → write A → read back → write B → read back → side effect only on
success. String-order pins (`strpos(writeA) < strpos(writeB)`) cannot prove "after a failed
read-back of A, B never runs", "no side effect after a refusal" or "a throwing side effect keeps
the success" — and the live walk cannot reach them either without a **patched build** (a debug hook
that injects the race between two statements). A verification step that says "temporary hook, not
committed" is the tell: the build being verified is not the build being shipped.

Move the sequence into a pure function and hand it its collaborators:

```php
interface WriteGateway { function getRowsByKeys(array $keys); function insertOwned(array $items);
                         function updateOwned(array $items);  function deleteOwned(array $keys); }

// pure: returns ['status' => int, 'body' => array, 'log' => string[]]
static function runSave($contentLength, $raw, $flagParam, WriteGateway $gateway, callable $sideEffect)
```

The model class `implements` the gateway (each method = one builder statement through the
adapter, source-pinned as before); the action shrinks to transport — read the request, call
`runSave()`, write the log lines, set status and body. The tests drive the orchestrator with a
**scripted fake**: a queue of row sets for the reads, every call recorded as `[name, argument]`,
an exception on any unscripted read so call-order assertions are real, and a spy for the side
effect. Cases that are now one assertion each: a row appears between the authorize read and
write A → 500, write B **not in the call list**, spy untouched; refusal → one read, no write; the
side effect throws → 200 stands and a log line comes back; keys that do not exist never reach the
delete call; the partial-write outcome the client contract warns about answers with **empty**
result lists. Keep one thin source pin on the action (it calls the orchestrator, reads the raw
body, maps the status) — that is all that is left to pin.

Check the interface's blast radius before adding `implements` to a hot class: if the model is
loaded on every request, confirm every entry point (web bootstrap, CLI runner, cron bootstrap)
registers an autoloader that can resolve the interface the same way it resolves the class's other
dependencies.

## Related

- `agents/AGENT_test-engineer.md` PASS 2 — the reviewer-side bullet that points here.
- Project-local pin recipes (whitespace-normalise before pinning SQL, strip comments before a
  negative assertion, `require_once` dispatcher-loaded classes) belong in the project's own
  solution docs; this file is the cross-project rule about *when a pin is not enough*.
