# A small optional parameter follows the action it joins — not the rule that was written for a bigger one

Load when a plan adds **one optional parameter** to a legacy action — a nullable column the
request may set, a flag, an ordinal — and the project's written API rule
([`NEW_PARAMETER_ON_A_LEGACY_ENDPOINT.md`](NEW_PARAMETER_ON_A_LEGACY_ENDPOINT.md) § 1 / § 8:
decide-first, a status code for the new path, a guarded write around the statement that names the
new column) is about to be applied in full. The rule is right for a parameter that **opens a new
path** (a filter that leaves the action, a compare-and-set, a second table, an external call). For
a parameter that only adds a value to a write the action already makes, applying it in full
produces a shape the owner will reject on sight — and did, four times on one PR, each time after
the engine had read the previous shape CLEAN.

## 1. The four shapes, and the objection each one drew

The field case: a nullable integer column on a child row (which guest of a booking a service is
for), an optional request parameter on the two legacy write actions of that row.

| Shape the plan / rule produced | The owner's objection | What replaced it |
| --- | --- | --- |
| A planning method answering 400 / 500 before the first legacy statement, **guarded write methods** wrapping the one statement that names the column (`catch (Throwable` → JSON 500, a log helper), pins on the lot | "Two separate methods for this — too much decorative logic for a small optional param." The only case the guard served is a tenant that received the code before the migration: a deploy-order error the hard migrate-first gate already forbids, which surfaces through the action's legacy failure path like any other DB error. | the value on the **legacy write** (one more optional argument on the model call; the key merged into the one `update()` array when sent) |
| One **private helper** in the controller (decide → 400 in the action's own failure shape) | "Both actions have their own param validation. Validate and throw just like it was done for `$qty`. Creating functions in a controller only for one param, when it has dozens of methods, makes it unreadable soon." | the refusal **inside the action's existing chain** — one more `$error = …` / `throw` next to its siblings, the action's legacy envelope and status |
| A **per-parameter value class** (pure, executed truth table: set / clear / invalid) | "Is it reasonable to create a whole service for one param? It is a nullable integer — useful for every integer param; we wouldn't copy that service for every such param. Reuse the framework's validators, it's more universal." | the framework's validator chain built inline (`Digits` → `Between`), the idiom the neighbouring controllers already use |
| A **literal domain maximum** in the chain (`Between(1, 2147483647)`) | "It's not ok to use such constants in code. The max is the sum of adults, children, teens, infants — see the check-in and guests managers." | the bound from the **model helper the siblings already use** (`getGuestsCount($id)`) |

The common thread: *the parameter must look like the parameters next to it.* Every shape the rule
produced was locally defensible and globally foreign to the file it landed in.

## 2. Decide the shape before writing the plan — four questions

1. **Can the new write fail on a *migrated* tenant?** A compare-and-set that can match nothing, a
   second table, an external call → the guarded write earns its place. A nullable column the
   legacy statement simply gains → it cannot; the only failure is a deploy-order error, and the
   gate (migrate first, written into the migration header, the contract and the PR) is the
   protection. No guard, no new 500 row.
2. **Does the action already have a validation section?** A `$error = …` chain, a `throw` chain, a
   form. Then the new parameter is one more link in it, refused in the action's own envelope with
   its own status — no private helper, no new status code, no "the outcome is told by the HTTP
   status" sentence. The house rule's 400 is for a *path* the parameter opens, not for a value it
   adds.
3. **Is the value rule parameter-specific?** "Nullable positive int", "one of N codes", "a date" are
   not. Use the framework's validators inline (grep the sibling controllers for the idiom —
   `Zend_Validate_Digits` + `_GreaterThan`, a DRF field, a form validator). A class per parameter
   is a copy waiting to happen under the next parameter's name. (Pure and well-tested is not a
   defence: the owner's objection was to the *existence* of the class, not its quality.)
4. **Where does the bound come from?** A maximum, a count, a range is a **model fact** — find the
   helper the siblings use for the same quantity (`getGuestsCount()`, a `max_*` column, a manager's
   limit check) and call it. Never a literal: not the column's type range, not a magic number. On a
   create, the bound may need the parent the request names (an unknown parent bounds nothing → the
   value is invalid, while the legacy acceptance of an unknown parent *without* the parameter stays);
   on an update, it comes from the row, so the check moves after the row is loaded — still before
   the write.

## 3. What still holds from the rule — it is not waived wholesale

- **Decide before the first write**, in the action's own order (the siblings' checks keep their
  precedence: `qty` first, then the new one); a refusal with the new value present writes nothing.
- **Absent must be the legacy path, byte-identical**: build the validator only when there is a
  value, never name the column when nothing was sent (the model sets the key only when non-null;
  the update array gains the key only when the parameter was present). Prove it with the
  before / after hash of the absent-parameter answers on the old and new build.
- **Present-empty vs absent is decided per parameter** — and when a present empty value is itself a
  write (an update that *clears*), presence is read from the request's parameter **keys**
  (`array_key_exists` on the merged params), never from the value accessor, which answers `null` for
  both. On a create where absent and empty coincide, the raw value is enough — don't carry the key
  check where it has nothing to distinguish.
- **The clear spellings are what the owner said and nothing more**: `''` and `0`. A literal
  `"null"` string, invented "for clients that stringify a JSON null", is a spelling nobody asked for
  and nobody will document — drop it with the class that held it.
- **Pin the shape, not the rule.** The source-level pins hold: the value read with the other
  parameters, the chain's two validators, the bound taken from the helper (and *no literal maximum*
  anywhere in the file), the refusal's position in the chain, one legacy write, nothing new caught or
  statused. The value rule itself is the framework's and is not re-tested.
- **Write the waiver into the rule text** ([`WAIVED_RULE_AMEND_THE_SOURCE.md`](WAIVED_RULE_AMEND_THE_SOURCE.md)):
  an exemption paragraph in the API rule saying when the ceremony is waived (one nullable column,
  nothing but the migration gate between the code and the column) and when it still applies (a
  parameter that opens a new path). Without it the docs-pass review and the next `/plan` re-raise the
  code against the rule as written.
- **Re-walk after each simplification** on the live stack, including the un-migrated case: the
  code's answer there changes with the shape (a JSON 500 under the guard; the error page / the
  legacy 200 with the driver text without it) and the contract's degrade row must say what is
  measured, not what was planned.

## 4. For the architect pass

A plan step that adds controller methods, a model class, a status code or a literal bound **for one
optional parameter** is a cost-benefit finding to put to the owner, not a blocker to uphold against
them. Ask the four questions of § 2 in the review; where the answers are "cannot fail on a migrated
tenant / the action has a chain / the rule is generic / the bound is a model fact", recommend the
action's own shape and say which clauses of the written rule still hold. The F1 that read "the
guarded write is mandatory, the contract's 500 row is false without it" was correct *about the rule*
and wrong *about the cost* — the owner answered it with the deploy gate.

## 5. When a later flag gates the parameter — the sequel keeps the shape

The follow-up almost always arrives: "only *some* items may take this parameter", so a boolean lands
on the catalogue the row is sold from and the action refuses the parameter for an unflagged item.
Everything above still holds, and five things are specific to the gate:

- **The flag's column lands on every table a wholesale copy writes to — the copy's target first.**
  A "sell" path that does `SELECT *` from the catalogue and `insert()`s the row into a snapshot
  table turns a catalogue-only column into an unknown-column error on every sale. One stem per table,
  the snapshot table's stem *first* in the batch, each pinned on its DDL and position; the snapshot's
  copy of the flag is informational — the gate never reads it (next bullet).
- **The gate reads the live catalogue, by the stored row's type and id — never the snapshot copy.**
  On create the item is looked up by the request's type + id; on update by the existing row's. Flipping
  the item's flag back refuses the next update while a clear still passes — put that row in the walk.
- **An executable type → table map on the model, not a comment that restates another method's
  dispatch.** The sell path already dispatches on the item type in its arms; the architect's ask is a
  small static map (`type → catalogue table`, unknown → none) the gate executes and the pins read,
  mirroring those arms — fail *closed*: an unmapped type (a custom / free-text row) refuses the
  parameter. A second comment copying the arm list drifts; a map that is executed cannot.
- **The gate is one more link in the same block, after the number check, and its lookup is
  skipped when the earlier link's input is empty.** `elseif ($id && !allowed(type, id))` on create;
  a second `throw` after the validator chain on update — so a missing id still answers the action's
  own "invalid id" text, not the gate's, and the gate's text is the second refusal line of the rule's
  exemption paragraph. A clear is always allowed (the gate runs only on a non-null value).
- **Reads carry the flag where the producer does.** A hand-built projection names the new column (and
  so needs the migrate-before-deploy gate); `select *` producers carry it for free; a list endpoint
  the owner excluded does not — which decides where the *schema* declares it (→
  `../../work/references/CAPTURE_FIRST_API_DOCS.md`, the shared-base trap).

## 6. A second small parameter beside the first — the sequel keeps the shape, and shares the gate

The next request is a sibling value on the same row ("which guest" was the first; "what kind of
guest" is the second): one more nullable column, one more optional parameter on the same two actions,
the same gate from § 5. Everything above holds; six things are specific to the second parameter:

- **A second block beside the first, not a merged one.** Merging both parameters into one block
  rewrites the first parameter's shipped code and every order pin on it; a hoisted memo (`$allowed`
  computed once above both blocks) is the decorative variable the owner refused. The second block
  copies the first's idiom — its own validator, its own clear spelling, its own refusal text — and
  depends on the first through **one condition**: the gate runs in the second block only when the
  first block did not run it (`$first === null` on create; `!($first_sent && $first !== null)` on
  update). That gives *at most* one lookup per request by construction. Pin "at most once" — never
  "exactly once": with the first value invalid, its block ends and the second block's condition is
  false, so the lookup runs **zero** times; the refusal text order is the chain's (last assignment
  wins on create, first `throw` wins on update) and the contract says so for a single failing link.
- **The pins the change falsifies are amended in the same commit as the code that falsifies
  them.** An eleventh argument on the writer breaks the first parameter's "last parameter" regex and
  its call-site needle; a second lookup site breaks the `substr_count(…) === 1` pins and a spec
  guard's "text once per action" count in a *different* test file. Scheduling the amendments one step
  after the code — as the first plan draft did — makes that step a red commit inside the PR. The
  architect's inventory of every count / regex / needle the change moves is the step-sequencing
  input; grep for the first parameter's symbol across the whole test tree, not only its own file.
- **The value rule is the framework's again, with the list as a model fact.** "One of N codes" is
  the framework's in-array validator in strict mode; the list is one constant on the model of the
  *domain the column mirrors* (the guest model for a guest band — not the service model that
  validates, or the arrow points the wrong way), built from the existing per-value constants, and
  the spec guard pins the column's enum equal to the constant. Grep the same class for a retyped
  copy of the list before writing "the only list in the code base" into its docblock — the setter
  next to the constants had one.
- **A type gate ahead of the validator, for both parameters — the refusal, not a `catch`.** The
  framework's validators throw only from configuration paths (a constructor without its option, an
  unknown message key) — constants here, so never at runtime. But `isValid()` on an array reaches
  the message builder's `(string)` cast: a logged warning under today's error settings, an HTML
  error page on the catch-less create action the day a warnings-to-exceptions handler lands on the
  request path, and an `Error` the update action's `catch (Exception)` does not see. `!is_string($x)
  || !$validator->isValid($x)` keeps a non-string away from every validator call, including the
  first parameter's (a cross-IDEA amendment, pins moved in the same commit). Read the validator
  sources before choosing: a `try` around each `isValid()` is the catch-per-parameter shape the
  owner rejected, and it protects against nothing the gate does not. Re-walk the array rows and
  count the warning lines before and after.
- **"Stop duplicating" has a named trigger.** Two blocks with one cross-block condition is the
  honest cost; a **third** sibling parameter on the same actions is the point to merge the blocks
  into one shared gate — write that sentence into the plan's decision so the next IDEA does not
  re-argue it.
- **The before / after hash of the absent-parameter path masks the row id.** A create response that
  carries the new row's id differs between the oracle and the branch on every run; compare with the
  id masked (`"id":"N"`) and say so in the verification doc — an unmasked "hashes differ" row reads
  as a behaviour change.

## Plan checklist

- [ ] The four questions of § 2 answered in the plan's decisions, each with the sibling idiom it copies (file:line).
- [ ] The action's validation section cited; the new refusal's position in it stated.
- [ ] The bound named as a model helper the siblings already call; a grep for literal maxima in the diff is empty.
- [ ] Presence-by-key only where present-empty ≠ absent; the clear spellings exactly the owner's.
- [ ] The rule's exemption paragraph in the plan's scope when the rule's ceremony is waived.
- [ ] The pins listed as *shape* pins; the framework's validator not re-tested.
- [ ] The un-migrated walk row restated after any change of shape.
- [ ] For a gating flag: one stem per wholesale-copy target, the snapshot's first; the gate reads the live catalogue; the type → table map is executed, unknown fails closed; the gate's lookup skipped when the earlier link's input is empty; the flipped-back walk row.
- [ ] For a second parameter: a second block behind one "the first block did not run it" condition, pinned as *at most* one lookup; every pin the change falsifies (last-parameter regex, call-site needle, lookup counts, the spec guard's text count — across the whole test tree) amended in the same commit as the code; the list a constant on the model of the mirrored domain, the class grepped for a retyped copy; an `is_string` gate ahead of every validator call for both parameters, array rows re-walked; the third-parameter merge trigger written into the plan; the create-response hash compared with the id masked.
