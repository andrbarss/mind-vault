# Capture-first API documentation — schema from a captured response ⊕ the DDL, never from the DDL alone

Load when a `/work` item is "document existing endpoint(s)" (OpenAPI / Swagger / any machine-readable
contract for code that already runs). The failure mode this prevents: docs written *about* the code —
from column lists, from one read of the handler, from what the endpoint "should" return — that drift
from what the wire carries. Two rounds of such docs on a downstream PHP project shipped wrong shapes
and a phantom `additionalProp1` in Swagger UI before the third round switched to this recipe and
documented 71 actions with every field backed by evidence.

## The rule

**No field lands in a schema without a captured response that contains it.** The DDL supplies
nullability and lengths; the capture supplies existence, wire type and shape. Anything only the code
promises (a branch that cannot be exercised safely) is marked *code-read* in the **verification guide**
— never in the published spec, whose readers do not care how you learned it (see
[`GENERATED_ARTEFACT_HYGIENE.md`](GENERATED_ARTEFACT_HYGIENE.md)).

## The recipe

1. **Inventory from the code.** Enumerate handlers mechanically (`grep 'function .*Action'`,
   route table, decorator scan) and reconcile with what the router actually serves (framework
   hyphenation / case rules, redirects for the wrong spelling).
2. **Verification guide before annotations.** One section per endpoint: handler location, params
   *as coded* (how read, cast, default, validation, line), success fields with the producing line /
   query, every non-200 / error branch, side effects, a **probe class** (`safe` / `needs-fixture` /
   `code-read-only`), open unknowns. It is simultaneously the reviewer's checklist and the capture
   plan — the plan's acceptance criterion is "every section ticked".
3. **Capture every branch** on a running stack — success, each error branch, the edge cases the guide
   predicts (unknown id, empty / non-numeric param, out-of-range date, wrong verb spelling). Store
   the exact request next to the body; trim collections to a few elements; redact personal data with
   a single key-list shared by the trimmer and a test; commit the captures as evidence with an index
   (request, status, content-type, shape). Non-JSON outcomes (empty 500, redirects, HTML error pages)
   are indexed, not committed.
4. **Mutations against throwaway rows.** Copy real rows into a reserved id range / prefixed keys,
   probe, delete, assert zero rows remain — the fixture *is* the rollback on engines without
   transactions. Side-effect paths (mail, external systems, payments) are probed only where nothing is
   delivered — a failing transport still yields the response shape — or stay code-read, and the guide
   says which.
5. **Schema = capture ⊕ DDL.** Wire types from the capture (decimals arriving as strings, ints as
   ints, observed nulls), lengths / nullability from the DDL, unobserved columns absent. **Never a
   wildcard `additionalProperties: true`** — omit it for `select *`-style rows whose column set drifts
   per tenant, set it `false` for computed objects. Shared column blocks compose via `allOf` so a row
   is described once.
6. **Id-keyed results** are `oneOf{<Name>Map, EmptyList}` when the serialiser emits `[]` for an
   empty map, and every map schema carries a **captured example** — UI renderers invent placeholder
   keys for maps without one. Key the example as the real response keys it (see the 0-key trap
   below).
7. **Generate the schema classes** from captures + DDL with a throwaway script per batch; hand-edits
   are where the drift starts. Keep the regenerated artefact under a drift test.
8. **Reconcile, then tick.** After capturing, record in each guide section what the probe confirmed
   and what it **corrected** — this is where the real bugs surface (unreachable "not found" branches,
   fatals on bad input, secrets in responses). Keep a *Findings register* in the plan and file it as
   follow-up ideas at wrap; do not fix in the docs PR.
9. **Structural guards in the suite**: every handler has an operation; one verb per path; every
   operation carries auth + the shared 403 + an operationId; every map has an example; no wildcard
   `additionalProperties`; no personal data in captures; no process / environment wording in spec
   text; artefact drift. Use a shrinking allow-list for not-yet-documented handlers across PRs and
   delete it when it reaches zero.
10. **Ship by handler group** (~10–15 per PR) so a reviewer walks one group's guide sections against
    one group's captures; the review bot should be able to run the generator + suite itself (see
    `review-loop/references/engine-claude.md` § reviewer cannot run the checks).

## Traps that recur

- **Nullability is inferred from observed values only.** A property whose description says "null
  when …" needs `nullable: true` explicitly; sweep `description` containing "null" without
  `nullable` before opening the PR.
- **A map example with a single `0` key serialises as a JSON list** in any language whose JSON encoder
  treats `0..n-1` keys as arrays (PHP, some Python paths) — the example silently stops suppressing
  placeholder keys. Key it as the real response does; if real keys start at 0, use two
  non-contiguous entries.
- **Loaders that never return empty** (they append computed keys to an empty row) make every "not
  found" guard unreachable: unknown ids answer success, may insert orphan rows. Capture the
  unknown-id case for every mutation.
- **Sibling-branch asymmetry**: an optional lock / handle released unguarded in the error branches but
  guarded in the success tail turns every refusal into a fatal when the optional param is absent —
  the self-sweep guard-return-asymmetry trigger, applied to docs probing.
- **Typed scalar parameters reject leading-numeric strings** on modern PHP (`"12abc"` → TypeError,
  not 12) — capture both the non-numeric and the leading-numeric variants.
- **An ungated handler is documented as the absence of a gate — and the guard asserts the absence.**
  A controller whose access check ends in an unconditional `return true` (the real checks commented
  out) must not inherit the sibling controllers' `security` + `403` docblock: its operations carry
  neither, the auth-dependent narrowing (`internal` rows, unlock keys) is stated per operation, and a
  login token that merely widens the result is an ordinary optional parameter. Keep the ungated set
  as a list of controller *files* whose URL prefix is derived the same way the coverage guard
  derives paths (so it cannot drift), and make the gate guard branch: gated → both schemes + the
  shared 403 present; ungated → both **absent**, with a positive control of at least one of each.
  A pasted gated docblock then fails the suite instead of publishing a 403 the server never sends.
- **The reachable surface of a subclassed handler is the router's, not the file's.** A subclass
  that declares one action and inherits seven dispatches all eight (with its type switch applied);
  a three-file family declared 11 actions and served 24 paths. Enumerate by reflection over the
  class chain (public `*Action`s declared by any class whose file lives under the application tree),
  document every reachable path, and let the coverage guard count inherited actions. When the
  annotation scanner accepts several operations in one docblock (swagger-php does — one path item
  per block, and scanning the subclass file never re-reads the parent's docblocks), put the
  inherited paths' blocks on the declaring method's docblock rather than on stub methods.
- **Composition conjoins; it does not override.** `allOf{Base, {field: pattern B}}` when `Base`
  already constrains `field` with pattern A is unsatisfiable (`required` + non-nullable over a
  nullable base likewise) — every real response fails the stricter branch, and only a strict
  validator or a reviewer notices. When variants disagree on a property, that property does not
  belong in the shared block: split it out and let each variant declare it once (raw DATETIME in
  one list, `DATE()`-truncated `Y-m-d` in another, `date()`-normalised with an epoch sentinel in a
  tree — the same column, three wire formats, three declarations).
- **Error paths with side effects get a probe budget.** A disabled action that throws into an
  error controller which renders under HTTP 200 *and e-mails support per request* is captured
  exactly twice (plain, and with `Accept: application/json`) under a `curl-once` probe class the
  guide states next to `safe` / `needs-fixture` / `code-read-only`; the plan records the total.
- **Probe every parameter once, including the ones that "obviously" work.** A list action's
  search parameter had never worked — the LIKE operand was quoted inside an already-quoted
  literal, the statement failed, and the caller received the error page under 200 plus a support
  mail. Nothing in the code read flagged it; the first capture did, and the operation now documents
  the parameter as broken rather than pretending it filters.
- **Post-action rendering interception**: an MVC framework whose view renderer runs after the action
  can replace the coded JSON with an error page for actions that forgot to disable rendering — the
  captured body, not the code, is the contract.
- **A trimmed capture is not a regression baseline.** The capture convention trims lists and
  maps to a few entries, so a committed `[5, 7, 8]` may be the head of a 13-element answer. A
  later change that must prove "the sibling endpoint is unchanged" cannot diff the live body
  against that file — compare against the producer's own SQL, or against a fresh untrimmed
  capture taken on the base branch with identical parameters (swap the one changed file in,
  capture, restore). State in the transcript *why* the committed capture differs.
- **A negative static-source pin must strip comments first.** When the suite cannot execute an
  action (DB-bound) and pins its *shape* by reading the method source through reflection, an
  assertion that a call is **absent** (`assertStringNotContainsString('getPacket(', $body)`)
  fails on the action's own comment that names the call it deliberately omits. Strip
  line comments before negative assertions; whitespace-normalise before pinning SQL text.

## ✅ DO / ❌ DON'T

- ✅ Write the guide section, capture, reconcile, *then* annotate.
- ✅ Say "not observed — derived from the code" in the guide and the PR body.
- ❌ Transcribe a column list into a schema and mark the endpoint done.
- ❌ Put "captured", "code-read", "verified on the dev stack" or the sprint's ids into the published
  description (→ `GENERATED_ARTEFACT_HYGIENE.md`).
- ❌ Fix the bugs the probes surface inside the docs PR — register them, file them, keep the docs
  PR comment-only in the handler file (a non-comment diff of the handler vs the base branch should
  be empty).
