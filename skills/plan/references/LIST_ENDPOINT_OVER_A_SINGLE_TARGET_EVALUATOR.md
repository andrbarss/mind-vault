# A list endpoint over a single-target action — run the action's evaluator per candidate

Load when a plan adds a read that lists **what an entity can do** next to an existing action that
**does one of those things** — "which packets can this reservation upgrade to" beside "upgrade this
reservation to packet X", "which slots can this booking move to" beside "move it to slot Y", "which
plans can this account switch to" beside "switch it". The listing's contract is *the set of candidates
the action would accept, with the numbers the action would answer*. Nothing else about it is new.

## The rule

1. **One evaluation path, extracted from the action — never a second copy pinned equal.** Move the
   action's per-target sequence (gates in order, each loader only after the previous gate passed, then
   the pure decision that produces the numbers) into one service method the action and the listing
   both call. A textual pin can keep two copies in step; only one executed path makes the list's verdict
   and the action's verdict identical *by construction*. The listing is then: the entity-level gates
   once, the candidate loader once, the shared evaluation per candidate, accepted candidates shaped into
   elements.
2. **Split the entity-level gates from the per-target gate.** The action's first gate usually mixes
   "this entity can never do this" (not found, wrong state) with "not *this* target" (already there).
   The listing needs the former without naming a target, so it can answer the empty list before any
   candidate loader runs. Extract it as its own pure method; the original delegates and keeps its
   messages byte-identical.
3. **Build the evaluator's collaborators lazily, so the single action's refusal load profile survives
   the extraction.** The action used to construct its pricing service *after* gate 7; a service that
   builds every collaborator in its constructor runs those constructors on every refusal the action
   used to answer for free — and a constructor that reads config or throws can turn a 400 into a 500.
   Protected factories (`createX()`) called on first use are the one test seam; drop constructor
   parameters nobody passes (an untested second seam). Execute this with recording doubles: a target
   refused at gate N never calls the factory gate N+1 would need.
4. **One instant per list.** Read the clock once outside the loop and pass it to every evaluation;
   any time-windowed gate then judges every candidate at the same moment. Say what happens to a
   candidate whose window closes between that instant and a later cache load (it is refused, as a
   single call at that instant would be) — and give the timestamp a test whose fixture makes the clock
   and the argument disagree (a window that closed a year before the argument), or a `time()`
   regression stays green forever (see `../../work/references/EXECUTE_OVER_PIN.md` § forwarded
   arguments).
5. **Memos are per request; the contract stays "uncached".** Memoise the candidate set and the shared
   lookups on the service instance, keyed by the *normalised* key (`(int)`), short-circuit the empty key
   without a statement, and write the lifetime into the class docblock: one instance per request, never
   held by a worker loop. A per-request memo does not contradict a contract that forbids cross-request
   caches; say so in the contract.
6. **Prove parity per candidate, from fresh requests.** For every listed element, call the single-target
   action in its preview / dry-run mode as a separate request and compare the numbers key for key —
   with and without the inputs that change pricing (a discount code accepted by one candidate and
   rejected by another). A fresh request per candidate is what exposes a cross-candidate cache leak in
   the list; a leak cannot show in the list's own output. Add the same element from a one-candidate and
   a two-candidate list: order-dependent leaks show there.
7. **Measure the per-candidate cost and name the unbounded dimension.** The list costs one full
   evaluation per configured candidate — statements, wall time, and any remote call the evaluation makes
   (once per candidate that reaches it, which may include candidates later refused). Record the count
   for one and for two candidates and the delta; when a remote dependency is down, measure what one
   request costs (timeouts add up per candidate, and a PHP-style execution-time fatal cannot answer the
   JSON envelope). Whether to cap the candidates or budget the remote calls is a product decision the
   plan leaves open *with the numbers*, not a default the plan invents.
8. **The empty list is a deliberate contract, written where the status-code rule lives.** If the
   product wants "unknown entity" and "nothing permitted" to be indistinguishable (200 `[]` for both),
   that departs from a "not found ⇒ 400" rule; amend the rule text with a narrow exemption naming the
   first use (`WAIVED_RULE_AMEND_THE_SOURCE.md`), and keep the malformed-id 400 and the 500 half intact.
9. **The listing widens disclosure.** The action already accepted any target the caller could guess; the
   list hands the ids and prices over, whatever the caller's access level. Name it in the plan's scope
   and in the operation description; it is a decision, not a bug.

## Anti-patterns

- ❌ Copying the gate sequence into the listing and pinning the two copies' text equal — the pin
  drifts the day someone reorders one; parity by construction is the only durable version.
- ❌ `new PricingService()` in the evaluator's constructor — every refusal now pays the pricing
  service's constructor, and the action's live answers change on the refusal paths nobody re-walked.
- ❌ A fixture whose time-windowed rows all have open windows — the timestamp is forwarded but never
  discriminated; `time()` passes.
- ❌ Verifying parity by comparing the list against itself, or against the action called *in the same
  request* — a shared cache leaks into both sides and the comparison passes.
- ❌ Writing "answers 500 when the external service fails" into the description because the dev image
  did — read the catch first (`VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md` § absorbed remote failure).
- ❌ Capping the candidate count "to be safe" before measuring — a silent truncation of an operator's
  curated map, decided without the number that would justify it.

## Related

- `COMPARE_AND_SET_GUARD_SCOPE.md` — the action's write side, untouched by the extraction.
- `PRODUCER_ARGUMENT_CONTRACTS.md` — every argument the action forwarded must reach the evaluator
  unchanged; the executed doubles pin the forwarding.
- `../../work/references/EXECUTE_OVER_PIN.md` — the recording-double shape for the evaluator.
- `SCHEMA_CONTRACT_HANDOFF.md` § second reader — when the candidate table is under a contract another
  repo mirrors.

**Last Updated**: 2026-09-14 (first version — extracted from a downstream listing built over a shipped
single-target upgrade action; the lazy-construction and one-instant rules came from the architect
review, the parity-from-fresh-requests and per-candidate-cost rules from the live walk).
