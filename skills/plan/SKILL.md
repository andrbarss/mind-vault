---
name: plan
description: Turn an IDEA file or rough feature description into a durable technical plan emitted into the idea's archive dir at docs/archive/YYYY-MM-idea-NNN-<slug>/YYYY-MM-DD-<slug>-plan.md. Interactively explores requirements when input is thin (brainstorm front-end merged in). Invokes AGENT_architect as a reviewer pass. Second stage of the mind-vault sprint workflow; aliased as /brainstorm.
---

# plan

Second stage of the five-stage sprint workflow (`idea → brainstorm/plan → work → review → compound`). Turns an atomic IDEA file or a rough feature description into a durable plan that an agent — or a human — can execute from without re-inventing product behaviour, scope boundaries, or test scenarios.

This skill merges the brainstorm + plan stages from CE. When input is already specific (a filled-out IDEA file, a bug report with clear repro), the skill skips straight to plan authoring. When input is thin (a one-line description, an IDEA stub), a **thin-input bootstrap** fires — the interactive brainstorm front-end — before the plan is written. Brainstorming is a mode, not a separate skill. `/brainstorm` is an alias for `/plan`.

This skill does not write code, run tests, or modify project source. It does, however, author the plan artifact and — per [`RULE_ideas-location-status`](../idea/references/IDEAS_LOCATION_STATUS.md) and step 6 below — trigger the single `git mv` that moves the source IDEA file from `docs/ideas/` into its `docs/archive/YYYY-MM-idea-NNN-<slug>/` dir. The plan artifact itself lands in that same archive dir (emitted by step 7). Execution belongs in `/work` (the next stage).

## When to use

**TRIGGER when:**

- user says "plan this", "write a tech plan", "plan the implementation", "how should we build X", "break this down", "what's the approach for Y", "let's brainstorm X", "help me think through X", "deepen the plan"
- user references an existing IDEA file by slug (`/plan sprint-workflow`) or path
- an IDEA file was just created by `/idea` and the natural next step is to turn it into a plan
- the user provides a bug report, a feature idea, or a rough description that would benefit from structured decomposition before execution

**SKIP when:**

- the work is a one-off trivial fix (typo, one-line bugfix) that a plan would over-engineer
- the user wants to start coding immediately on something well-understood — route to `/work` directly
- the user is still exploring "what to build" at a portfolio level with no single target in mind — route to `/idea` (or multiple `/idea` invocations) to surface candidates first

## Pattern

### 1. Resume, source, and scope

Before drafting anything, check for existing work and classify the input.

1. **Check for an existing plan.** Plans live inside the source IDEA's archive dir per step 7 (`docs/archive/YYYY-MM-idea-NNN-<slug>/YYYY-MM-DD-<slug>-plan.md`); there is no separate `docs/plans/` tree. If the slug (explicit argument or derived from the input) matches `<project>/docs/archive/*-<slug>/*-<slug>-plan.md`, offer to continue: "Found `2026-04-19-sprint-workflow-plan.md` in `docs/archive/2026-04-idea-042-sprint-workflow/`. Resume or start fresh?" Default to resume unless the user says otherwise. For orphan plans with no source IDEA (per step 7's Special cases) or pre-refactor plans still sitting in a legacy `docs/plans/` tree, also fall back to a repo-wide `*-<slug>-plan.md` glob as a best-effort.
2. **Resolve the input source.** Accept in order: IDEA file path, IDEA slug (`/plan sprint-workflow` → glob **both locations** `docs/ideas/IDEA-*-sprint-workflow.md` AND `docs/archive/*/IDEA-*-sprint-workflow.md`, since an already-in-progress idea has been moved to its archive dir per step 6 and a deepening pass must still find it), plan-file path for deepening, raw description in the command argument, or nothing (ask the user what to plan).
3. **Classify scope** early: trivial / small / medium / large. Trivial skips out of the skill entirely. Small gets a compact plan. Medium and large get the full structure. Do not force ceremony onto work that doesn't need it.

### 2. Thin-input bootstrap (brainstorm front-end)

When the input is thin — a one-liner, an empty IDEA stub, or a description with evident gaps — enter interactive mode before drafting the plan.

Thin-input indicators:

- IDEA file has fewer than ~3 substantive prose paragraphs in the body.
- Raw description is under ~30 words.
- No success criteria, no scope boundary, no constraints surfaced.
- Multiple valid interpretations of what the user wants.

When thin, run the bootstrap per [`references/thin-input-bootstrap.md`](references/thin-input-bootstrap.md): one-question-at-a-time, prefer single-select blocking question tools, capture decisions in-memory, then proceed to plan authoring with the enriched context. Bootstrap output may also update the source IDEA file's prose body if one exists — confirm with the user before writing back.

Not thin — skip the bootstrap and go straight to step 3.

### 3. Research before structuring

Before drafting the plan, do the research the plan depends on.

- **Repo pattern scan.** Grep for existing abstractions the work should reuse — base classes, utility functions, similar features. Do not propose new code when a suitable implementation exists.
- **Institutional-learnings pass.** Check `<project>/docs/solutions/` for prior solved problems tagged with overlapping keywords. Check `mind-vault/skills/*/SKILL.md` and `mind-vault/rules/RULE_*.md` for cross-project patterns that apply.
- **External-references pass (only when warranted).** If the plan depends on framework behaviour, SDK semantics, or a spec the agent isn't sure of, note the reference; surface ambiguity in the plan's Open Questions section rather than guessing.

Right-size the research — a one-session fix doesn't need a literature review.

### 4. Draft the plan

Read [`assets/plan-template.md`](assets/plan-template.md) and fill its sections. Canonical plan structure (mirrors the CE-inspired shape that this mind-vault plan was itself written in):

1. **Context** — why this work, what prompted it, intended outcome.
2. **Problem Frame** — what's broken or missing, how it hurts today.
3. **Requirements Trace** — R1, R2, … each traceable back to the IDEA body or the user's request. Tag every criterion only a human can satisfy (a real-device matrix, physical hardware, a third-party console) `(human)` and say whether it **gates close-out** or is a **recorded follow-up** — an untagged human-only criterion merges review-clean and then blocks the IDEA from ever closing; see [`../wrap/references/IDEA_COMPLETENESS_AUDIT.md`](../wrap/references/IDEA_COMPLETENESS_AUDIT.md) § Human-only acceptance criteria.
4. **Scope Boundaries** — in-scope / out-of-scope / explicit non-goals.
5. **Context & Research** — existing code and patterns to reuse (with file paths), institutional learnings, external references.
6. **Key Technical Decisions** — opinionated defaults with one-line rationale each.
7. **Open Questions** — things that need user input before execution starts. Suggest a default per question; mark resolved questions inline.
8. **Execution Sequence** — ordered steps (files to create/modify, commands to run, tests to write).
9. **Verification** — how to confirm the work lands correctly. Commands or checks, not vibes.

Plan quality bar:

- Repo-relative file paths everywhere. Never absolute.
- Concrete file paths in the execution sequence, not "the auth module".
- Test scenarios listed per feature-bearing unit, specific enough that an implementer knows exactly what to test without inventing coverage.
- Decisions carry rationale, not just names.

### 5. Architect reviewer pass

Once the draft is written, invoke `AGENT_architect` as a reviewer. Not as author — the plan is already drafted. See [`references/architect-handoff.md`](references/architect-handoff.md) for the handoff protocol.

The architect's 4-pass workflow (abstraction/genericity sweep → coupling/dependency probe → boundary contradiction analysis → deployment/scaling pre-check) produces a verdict: ARCHITECTURALLY SOUND, REQUIRES ABSTRACTION, or REJECTED. Incorporate findings before marking the plan `status: ready`.

The reviewer pass is optional for trivial and small plans. Required for medium and large.

### 6. Transition the source IDEA — single move, then never again

Per [`RULE_ideas-location-status`](../idea/references/IDEAS_LOCATION_STATUS.md), the act of drafting a plan is the signal that an idea has left the backlog. This triggers the **one and only** filesystem move in the IDEA file's life — and it must run **before** step 7 writes the plan file, because step 7 emits the plan into the dir this step creates:

```bash
mkdir -p <project>/docs/archive/YYYY-MM-idea-NNN-<slug>/
git mv <project>/docs/ideas/IDEA-NNN-<slug>.md \
       <project>/docs/archive/YYYY-MM-idea-NNN-<slug>/IDEA-NNN-<slug>.md
# + update frontmatter: status: in-progress
# + update docs/ideas/README.md: move the entry from its priority section
#   into "🚧 In Progress" (link now points at ../archive/<dir>/)
```

`YYYY-MM` = current month. Stays fixed across the rest of the idea's life — neither completion nor rejection renames this dir.

**Verify the number before the move — `/plan` is the last cheap place to renumber.** `/idea` allocates from the on-disk trees plus sibling branches (idea skill § 4), but a capture made on a stale checkout can still carry a number that a shipped idea or an unmerged sibling branch already owns. Grep `docs/archive/*idea-NNN*`, `docs/ideas/IDEA-NNN-*` and the remote `idea-NNN` branch names for the number; on a collision, renumber to the next free one **as part of this step** — the `git mv` target dir and filename take the new number, `id:` in frontmatter and the `# IDEA-NNN:` heading follow, and the status line records "captured as NNN, renumbered at `/plan`" so the index and the devlog can explain the jump. After the plan is emitted the number is referenced from the plan, the contract, the branch names and the PR titles, and a rename becomes a multi-file sweep.

After this step's move, step 7 emits the plan file into the same dir. All subsequent artefacts (research notes, session prompts, screenshots, the eventual README) go into this dir too. Future `/work` on completion edits frontmatter to `status: complete` — **no further file movement**.

**Always run this step when `/plan` is invoked**, even for trivial or small scopes. Earlier drafts allowed skipping the move for small scopes; that created a gap where a complete IDEA could end up sitting in `docs/ideas/` (location-status mismatch per `RULE_ideas-location-status` hard rule #2). `/plan` is the primary owner of this transition; if the user bypassed `/plan` entirely and went straight to `/work`, `/work` performs the same move as a fallback.

### 7. Emit the plan file into the idea's archive dir

Plans live **alongside the IDEA file they implement**, inside the same `docs/archive/YYYY-MM-idea-NNN-<slug>/` dir per [`RULE_ideas-location-status`](../idea/references/IDEAS_LOCATION_STATUS.md). There is no separate `docs/plans/` tree — that was an earlier draft and was dropped in favour of co-location (cross-refs between plan and IDEA file stay local; no cross-tree paths).

Step 6's move has already created the archive dir and moved the IDEA file into it, so this step just writes the plan file alongside:

```text
docs/archive/YYYY-MM-idea-NNN-<slug>/
  ├── IDEA-NNN-<slug>.md             # moved here in step 6
  └── YYYY-MM-DD-<slug>-plan.md      # emitted here in step 7
```

Stage-handoff frontmatter:

```yaml
---
stage: plan
slug: sprint-workflow
created: 2026-04-19
source: ./IDEA-NNN-<slug>.md                # relative to the plan's own dir
status: draft                                # draft | ready | shipped
project: <project-name>
---
```

Print the created path + a one-line summary. Suggest `/work <plan-path>` as the next command.

**Special cases** (skip step 6's move, emit the plan differently):

- The source IDEA file already lives in `docs/archive/<dir>/` — this is a plan revision on work already in-progress or a re-plan after rejection; just emit the new plan into the existing dir. Step 6's move was already done by the original `/plan` run.
- There is no source IDEA file — the plan is a standalone artefact; emit it to a context-appropriate location (often `docs/plans/` as a fallback, which exists only for orphan plans). Step 6 doesn't apply because there's nothing to move.

Commit message for the combined IDEA-move + plan-emit change: `docs(plan): <slug> — draft plan + move IDEA-NNN to in-progress`.

## Right-sizing the artifact

| Scope | Plan structure |
| --- | --- |
| Trivial (typo, one-liner) | Skip the skill entirely — just do the fix |
| Small (bounded, < 30 min, single file) | Context + Scope + Execution Sequence only (~50 lines) |
| Medium (feature with clear boundaries) | All sections, brief (~200 lines). Architect review required. |
| Large (cross-cutting, multi-file, unknown unknowns) | Full plan, phased execution, architect review mandatory, open questions explicit |

The plan's philosophy stays the same at every scope; the depth scales.

## Interaction rules

- **One question at a time.** Never batch unrelated questions into a single message.
- **Prefer single-select** blocking-question tools (`AskUserQuestion` in Claude Code, `request_user_input` in Codex) for direction choices. Multi-select only for compatible sets (constraints, success criteria).
- **Short sections, brief bullets.** The plan is a reference document for executors, not a manifesto.
- **Repo-relative paths everywhere.** Absolute paths break portability across machines, worktrees, and teammates.

## When NOT to use these patterns

- **You're already in `/work`.** Don't re-plan in the middle of execution; update the plan's Open Questions section and handle execution-time unknowns inline.
- **The user wants to capture a new idea, not plan existing work.** Route to `/idea`.
- **The work is one-off and known.** A typo fix does not earn a plan.
- **You're documenting a solved problem.** Route to `/compound`, not `/plan`.

## References

- [assets/plan-template.md](assets/plan-template.md) — the verbatim plan structure the skill emits
- [references/thin-input-bootstrap.md](references/thin-input-bootstrap.md) — the interactive brainstorm front-end for thin inputs
- [references/architect-handoff.md](references/architect-handoff.md) — how to invoke AGENT_architect as a reviewer and integrate findings
- [references/batching-for-sprint-auto.md](references/batching-for-sprint-auto.md) — opt-in mode for grouping multiple `/plan` outputs onto one feature branch + PR to feed an overnight `/sprint-auto` run
- [references/PROD_DATA_SNIFF_BEFORE_DESIGN_LOCK.md](references/PROD_DATA_SNIFF_BEFORE_DESIGN_LOCK.md) — when a plan's design hinges on a data-shape assumption verified only in dev, require a prod-data sniff before commit OR document a dev-as-proxy override with rationale
- [references/VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md](references/VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md) — a subsystem's runtime-shape claim (global vs per-tenant config, request lifecycle, multi-tenancy) can't be confirmed by reading code at one point; it's a blind spot for fan-out agents AND review bots — trace the lifecycle or flag for human confirmation before locking it into a reference/plan; sibling traps inside: phantom verification, a mid-flight producer, a time-anchored branch, and **sign-to-magnitude promotion** (a boolean promoted to a count exposes every inflation the sign absorbed — verify with an independent count, never with parity against the sibling that shares the reducer)
- [references/PRODUCER_ARGUMENT_CONTRACTS.md](references/PRODUCER_ARGUMENT_CONTRACTS.md) — load when a plan reuses a shared producer and passes or omits one of its scoping arguments: classify each argument by reading the branch (additive / narrowing / defaulting / switching), then trace it to the exact call site the plan uses — a narrowing loader behind a call that never forwards the argument is scope-independent by construction; state the residual's direction, make the probe's signal vary with it, and name the per-row baseline every cost claim excludes; and when the plan *widens* a scope with a switch in front of a narrowing argument, enumerate the call sites by argument (every setter flips, not just the feature's endpoints), pin the ones that must not follow, keep "no argument = everything" for the un-scoped callers, and design the partial-opt-in state
- [references/SCHEMA_CONTRACT_HANDOFF.md](references/SCHEMA_CONTRACT_HANDOFF.md) — when a schema change is consumed by a parallel team / codebase (admin write-side, sibling service, client generator), emit a plan-stage `schema-contract.md` (exact UP/DOWN DDL + composable writer invariants + a seed probe with expected output arithmetic) into the idea's archive before /work; the migration mirrors it verbatim and the seed probe doubles as both codebases' acceptance check; when the table's owner has not planned yet, write a *requesting* contract, gate the scaffolding on a re-read, and mirror every revision with a banner md5 the suite re-hashes and a drift guard that parses the DDL out of the mirror; before emitting a build contract, read the consumer's note on its branch, and never emit a selection flag next to a record that already carries the selection
- [references/REVERSIBLE_EXPIRY_ON_TWO_PHASE_HOLDS.md](references/REVERSIBLE_EXPIRY_ON_TWO_PHASE_HOLDS.md) — load when a plan adds a reaper / TTL job over a two-phase hold: the expiry releases a hold whose downstream writer deliberately skips the availability check, so revival must re-validate at the revival site (demand-aware), the un-cancel must be marker-conditional and single-statement, and the cutoff must be evaluated on whichever clock writes the timestamp
- [references/UNIQUE_KEY_TWO_LAYER_WRITER.md](references/UNIQUE_KEY_TWO_LAYER_WRITER.md) — load when a plan adds an application-written UNIQUE column (slug / short code / handle): normalise only the types you accept (a normaliser moved ahead of the validator sees arrays), validate the normalised payload, an *unlocked* pre-check for the friendly message, an errno-only integrity-error catch as the guarantee, the collation as the shared comparator, and a conflict exception whose base class no sibling catch already maps elsewhere
- [references/WAIVED_RULE_AMEND_THE_SOURCE.md](references/WAIVED_RULE_AMEND_THE_SOURCE.md) — load when a plan decision deliberately departs from a convention the project has written down (an API status-code rule, a "new endpoints must …" checklist): the plan schedules an edit to the rule text itself — a general exemption + backref + docblock citation — in the same PR, because a waiver that lives only in the plan / PR body is invisible to the review engine that enforces the written rule
- [references/API_OWNED_ROWS_IN_A_SHARED_TABLE.md](references/API_OWNED_ROWS_IN_A_SHARED_TABLE.md) — load when a plan gives an API client a create / update / delete path into a table other writers already own: an ownership flag whose DEFAULT keeps every legacy writer correct, the adopt-empty-stub carve-out when reads write, an all-or-none `INSERT … WHERE NOT EXISTS` where no UNIQUE key is possible, one comparator per concept on both seams (index-friendly exact key pair, length-based emptiness — `= ''` is true for `' '` and a mixed-collation column breaks multi-column expressions —, the flag's driver type), refusing what the storage silently corrupts, idempotent re-send as the convergence story
- [references/RAW_BODY_ENDPOINT_HARDENING.md](references/RAW_BODY_ENDPOINT_HARDENING.md) — load when a plan adds an action that reads a raw JSON / XML body: a size cap "before the read" is defeated when the read is a function argument (decide in the transport, pin the order), credentials forced into the query string meet request-URL loggers, strict decode (objects as objects, a pinned depth), error text that echoes client-sized keys once per problem (cut it, bound the fan-out, give clipped identifiers a position), and staged validators that make "every item is evaluated" false
- [references/WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md](references/WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md) — load before writing any "nothing reads this data" claim into a plan or IDEA: a `SELECT *`-and-dump endpoint emits rows it never names, so a symbol grep returns zero and the negative is wrong; grep the container for wholesale emitters too, and expect the same value to carry different types on a wholesale vs a curated surface
- [references/CONTRACT_CONSUMER_DISCIPLINE.md](references/CONTRACT_CONSUMER_DISCIPLINE.md) — load when a plan builds *against* a contract another codebase emitted at its plan stage (the consumer side of `SCHEMA_CONTRACT_HANDOFF`): a `[]`-means-clear write key derived from an asynchronously loaded reference list must be gated on that list's *successful* load and stay absent otherwise (an early Save or a transient load failure otherwise wipes every value, and the specs are green on the broken design); the contract is a moving target until its owner's `/wrap` — re-read it at the end of `/work`; and when the runtime walk is blocked, verify every envelope root, flag read and create-vs-update key against the producing code with `file:line`; read wire booleans through a truth table, never `!!` (the producer's cast exists because its DB hands a `TINYINT` back as `"0"`); and prove an invariant `change` handler stays silent under a programmatic multi-field set with an event spy plus a positive control, never a transition; restore a gated key's original value when the gate closes after a failed save; with no contract yet, send the producer a consumer note and ask for a dedicated list route that doubles as a provisioning probe; and never decide reload-vs-retry on a 2xx partial-success envelope the producer also emits when nothing saved; assert payloads through the whole write path once it has a later stage (a transform the per-record serialiser never reaches), and label every sentence your note makes about your own client *measured* or *predicted* — a producer adopts the note verbatim
- [references/STRICTER_WRITER_NEEDS_A_CLIENT_EXIT.md](references/STRICTER_WRITER_NEEDS_A_CLIENT_EXIT.md) — load when a plan adds a write rule the storage does not enforce ("at least one flag on", a non-empty list) over rows another system can also populate, and the read-back is faithful: a client that re-sends a legal-but-refused state unchanged (retired / disabled rows) is locked out of every save — decide the exit at plan time (a load-bearing seed rule in the consumer contract, or a writer carve-out in the phase that knows the entry's class) and, when the rules amend a shipped contract, ship one authoritative delta with pointers in the amended file instead of two drifting copies; a fourth exit hides a meaningless refused row at the reader when every other reader already ignores it
- [references/WINNER_IDENTITY_THROUGH_A_MIN_FOLD.md](references/WINNER_IDENTITY_THROUGH_A_MIN_FOLD.md) — load when a reducer that reports a minimum / best must also name the candidate behind it: carry the winner beside the number (one per minimum — the cheapest night need not sit in the cheapest stay), pin the tie-break in the reducer by sorting candidates on a by-construction-unique tuple (a loader's `SELECT` without `ORDER BY` is not a contract, and an engine mode never sees the SQL), state and probe the uniqueness an emitted resolved id relies on instead of widening the producer, verify the name with an independent derivation rather than sibling parity, and grep guard-test pins before splitting commits — a pin that walks a committed example drags the schema into the reducer's commit
- [references/COMPARE_AND_SET_GUARD_SCOPE.md](references/COMPARE_AND_SET_GUARD_SCOPE.md) — load when a plan protects a write computed from an earlier read with a conditional `UPDATE … WHERE key AND <expected state>`: guard every column the computation read (not just the one the write changes), a NULL expectation is `IS NULL`, an after-update hook that re-selects with the guarded `WHERE` never sees the moved row (fire it by key), rows changed ≠ rows matched
- [references/CLAIM_BEFORE_SIDE_EFFECTS_NEEDS_A_WAY_BACK.md](references/CLAIM_BEFORE_SIDE_EFFECTS_NEEDS_A_WAY_BACK.md) — load when a plan closes a race by claiming a state transition *before* the work it gates (order row, code, outbound call): a failed first effect now strands a claimed record that every retry path refuses to enter — release the claim guarded to the bare state with the previous state read before the claim, make the release unable to throw over the original exception, free every outer idempotency lock on the way out (else the caller's repeat is acknowledged "already processed"), walk the heal live with the **same** key, and check whether the handler's amount precondition is replay-stable (a credit the half-completed first call consumed no longer reduces the total)
- [references/STATE_WATCH_ON_A_SHARED_CHECKOUT.md](references/STATE_WATCH_ON_A_SHARED_CHECKOUT.md) — load when a plan adds a periodic job that fires effects on a boundary the data does not record (a clock window, a visibility range, midnight): the last-seen state lives in a per-tenant table, never a file on a multi-tenant checkout; the state string carries the date when its meaning rolls over; one-statement claims with the first contact decided on purpose; collaborators built before the claim, every effect isolated, restore only a claim whose effects never started, and the fallback that recovers each failed effect named; the lag per consumer; the un-migrated deployment as a normal state; the eleven walk rows
- [references/NARROWEST_CHANNEL_BOUNDS_THE_RULE.md](references/NARROWEST_CHANNEL_BOUNDS_THE_RULE.md) — load when a plan changes what a price / discount / availability means and the value reaches several channels (storefront, feeds, OTA exports): read every exporter's unit off its loop and fixed arguments before locking semantics, set the rule at the narrowest unit or scope it per channel explicitly, exclude a category a channel never carries, treat the push cadence as part of the rule, and remove a dropped wider variant strictly across plan, contract and sibling repositories
- [references/FILTER_A_DERIVED_STRUCTURE_BY_SELECTING_FROM_IT.md](references/FILTER_A_DERIVED_STRUCTURE_BY_SELECTING_FROM_IT.md) — load when a plan adds a filter / search / "only mine" view to an endpoint whose answer is a derived structure (a cached lookup map, a merged catalogue, a fold): call the same producer and remove entries (subset by construction) instead of deriving it a second time in SQL, shrink the storage need to a membership list, match key filters in code (no `LIKE`), decide complement semantics as a partition — and trace the structure to the point it reaches the caller, because a post-fold transform (a merge helper that renumbers integer keys) means some keys never survive and must not be matched against storage; fixtures go through the producer's own transform; both staleness directions in the contract; verify by independent derivation
- [references/REUSED_VALIDATOR_FAILS_OPEN.md](references/REUSED_VALIDATOR_FAILS_OPEN.md) — load when a plan re-runs a creation-time validator (stock, quota, sales window) on a new path: lookups answer `false` on failure and validators written for arrays *pass* on it — a pure fail-closed verdict first, scope parity with the counter, validate the delta; and the over-correction: refuse *could not load*, never *loaded and not the counted type* (a caller-set flag on an uncounted type otherwise refuses for ever)
- [references/NEW_PARAMETER_ON_A_LEGACY_ENDPOINT.md](references/NEW_PARAMETER_ON_A_LEGACY_ENDPOINT.md) — load when a plan adds an optional parameter to a legacy endpoint with existing callers and a non-conforming (always-200, bare-payload) contract (§ 8: a *write* parameter cannot leave the action — decide first, check the plan against the action's own read, one routed write, the missed guarded write on the new status): decide invalid / absent / **empty** per parameter with the user and write the resolution into the project's rule text in the same PR, keep the bare success body so the HTTP status is the only discriminator (`success` can be a legal key of a map payload), branch out before the first legacy statement into a non-routable method, pin both halves at source level and hash the untouched response before / after, force a real 5xx through something only the new path names, grep earlier hand-off contracts for sentences the change makes false, and lead the hand-back with "nothing changes unless you send it"
- [references/AMEND_A_QUEUED_TASK_PAYLOAD.md](references/AMEND_A_QUEUED_TASK_PAYLOAD.md) — load when a plan writes into the stored payload of a task that is already queued (a deferred registration, a retryable outbound call): a conditional `UPDATE` on status **and** the whole payload so a lost race cannot erase the worker's idempotency ledger; refuse a payload whose ledger makes the worker skip the stage that reads your key (a silent loss that looks delivered); every other read-modify-write writer of the payload is the residual race — name it; a second source of a presence-signal key changes its meaning for the consumer
- [references/LOCAL_FLAG_INTO_AN_EXTERNAL_RECORD.md](references/LOCAL_FLAG_INTO_AN_EXTERNAL_RECORD.md) — load when a plan starts sending a locally stored flag (consent, opt-in, preference) to an external system that keeps its own longer-lived record: a `NOT NULL DEFAULT` column cannot say "never asked", so presence of the input is the signal and non-answering writers, imported rows and update calls send nothing; one external field fed from two local copies (booking vs person) flips back and forth — one sink, latest answer wins, both directions, same-person siblings, executed not pinned; a lossy legacy writer becomes an external write — check the real client's form in its own repository; a later change goes by a narrow call behind a per-consumer capability flag, only for values that moved, as delivery-only statements around the unchanged writer
- [references/IDENTITY_PARAMETER_ON_A_SHARED_SECRET_CALL.md](references/IDENTITY_PARAMETER_ON_A_SHARED_SECRET_CALL.md) — load when a plan adds "who is calling" to every outbound call that already carries a shared credential: take the value from where the process already records its own identity (the queue's task `source`, never the request host), read it once through a guarded read and name every env shape, absent never empty, one url builder for N sites with unset-then-set against smuggled keys, a header cannot reach a url-only queue, the value is routing context **never authorization** (any holder of the secret asserts any identity), and when the consumer's source is out of the workspace the check is a human pre-deploy probe that gates the deploy, not the close-out; date the sibling docs the change makes false
- [references/LIST_ENDPOINT_OVER_A_SINGLE_TARGET_EVALUATOR.md](references/LIST_ENDPOINT_OVER_A_SINGLE_TARGET_EVALUATOR.md) — load when a plan adds a read that lists what an entity can do next to an action that does one of those things: extract the action's per-target evaluator and call it from both (parity by construction, never two pinned copies), split the entity-level gates from the per-target gate, build the evaluator's collaborators lazily so the action's refusal paths keep their load profile, one instant per list with a fixture that discriminates it, per-request memos, parity proven per candidate from fresh requests, the per-candidate cost measured before any cap, the empty-list contract written into the status-code rule
- [references/SET_REPLACE_UNDER_EMPTY_RANGE_LOCKS.md](references/SET_REPLACE_UNDER_EMPTY_RANGE_LOCKS.md) — load when a plan serialises a delete + reinsert of a child set with `FOR UPDATE` / `select_for_update()`, or any text claims a lock "serialises concurrent saves": a parent row on a non-transactional engine (MyISAM) locks nothing, an empty InnoDB range takes a *shared* gap lock so two inserting writers deadlock instead of queueing (and collide on a duplicate key under READ COMMITTED); prove it with a two-session probe in which **both** sessions insert, timed on the database host; serialise by retrying the whole replace, translate only residual conflicts, never inside a caller's transaction
- [references/ADDITIVE_COLUMN_THROUGH_ALLOW_LISTED_WRITERS.md](references/ADDITIVE_COLUMN_THROUGH_ALLOW_LISTED_WRITERS.md) — load when a plan adds a column to a row written by several actions through explicit allow-lists and read by wholesale emitters: inventory every gate (shared form, per-action lists, the placeholder row a reader fabricates, projection lists) and pin copied lists identical; normalise once at the shared sink because form validation never mutates the caller's array (a pure static, key-presence guarded, non-scalar case decided); pick the blank filter's mode on purpose (`'0'` is a value); state the error shape **per writer / proxy** in the contract with one over-length value walked through each; teach the capture redaction guard before the first capture; land every spec annotation in one commit against a drift guard; read the table's charset/engine from `information_schema` at step 0, never from a cited dump
- [references/ROUTE_A_VARIANT_THROUGH_A_SHARED_WRITER.md](references/ROUTE_A_VARIANT_THROUGH_A_SHARED_WRITER.md) — load when a plan adds a variant of an existing sale / creation through a writer several callers share and the obvious route is the writer's "no parent" branch: grep the record's type classifier first (it may key on a join row the writer inserts only for a parent — the variant is then a *different type* to every downstream gate), key the new arm on the *presence* of the new field so the siblings are untouched by construction and pin the caller count, return an arm's value untouched when a hash / idempotency key derives from its text (`assertSame` on the string), pass the decision's DB facts as lazy callables so the legacy row reads nothing, gate numeric strings on finiteness + a ceiling, and name the listing filters the sale does not share
- [references/PASS_THROUGH_PROXY_CONTRACT.md](references/PASS_THROUGH_PROXY_CONTRACT.md) — load when a plan adds a field to, or documents, a write an intermediate service forwards without reshaping: where the validator lives is decided by what the *client's* failure renderer can turn into a message (a proxy-side "house shape" can render worse than the upstream's), "verbatim relay" is a per-status-class claim (an HTTP client without error passthrough turns every non-2xx into the proxy's own 500 — state it, pin it, never flip the shared client in passing), and the field inherits the path's gate, allow-list and request loggers — name that exposure, don't widen scope
- [references/OPERATOR_LIST_THAT_RECEIVES_A_SECRET.md](references/OPERATOR_LIST_THAT_RECEIVES_A_SECRET.md) — load when a plan adds an operator-typed list (URLs, hosts, webhooks) and every accepted entry is then sent a credential: drop never repair (refusal reasons, per-label hosts, the port *text*, no integer / hex address spellings), the platform's URL parser is not a validator (send the URL rebuilt from validated parts; address filters differ between runtime versions — judge the embedded IPv4), cleartext only to an internal *destination*, **nothing of a refused entry is rendered** (three "safe part" renderings each leaked → position + reason + length, the text never leaves the validator), the primary compared leniently, the sinks written down, locate your own secret by key not by line number, a preflight that keeps the key out of history and the process list
- [references/SECOND_SOURCE_FOR_AN_OPS_ONLY_SETTING.md](references/SECOND_SOURCE_FOR_AN_OPS_ONLY_SETTING.md) — load when a plan gives a setting that lived only in env / server config a second, higher-priority source in a store the application can write: precedence as a truth table the owner answers (replace or merge, all-refused, how to say "none", unreadable, unregistered) behind a pure chooser whose emptiness is a superset of the validator's trim, **every writer of the store listed — if any can create the row, the human security check gates the DEPLOY, not "enabling the feature"**, one comparator on reader / hide filter / migration, hide at the emitter not in the list method that doubles as the existence check, and what moved with the source (validation assumptions, downstream weaknesses, audit trail)
- [references/FAN_OUT_THROUGH_A_SHARED_SERIAL_QUEUE.md](references/FAN_OUT_THROUGH_A_SHARED_SERIAL_QUEUE.md) — load when a plan turns "call one target" into "and queue the same call for N more" over a queue shared with unrelated work and drained one task at a time: time the request *and* the drain (an unrelated task queued behind the bad one), read the consumer (single-flight, connect / total timeouts, redirects, whether the adapter stores a task timeout, what the last failed try emits), the failure-mode table with measured / by-the-code per cell (grep for an existing stale-claim reset before writing "nothing resets it"), synchronous methods become producers — some on customer traffic —, opt-in per method plus a test that classifies every public method, and a catch-all that needs a per-entry-point probe of what it swallows
- [references/ADDITIVE_COLUMN_THROUGH_A_WHOLESALE_COPY.md](references/ADDITIVE_COLUMN_THROUGH_A_WHOLESALE_COPY.md) — load when a plan adds a column to a table and any writer builds an `INSERT` into a second table from a `SELECT *` of the first (a catalogue row snapshotted onto an order line): the copy names no column, so the destination gains it FIRST in its own migration with the dependency in both headers; two ordered migrations, not two `ALTER`s in one file; a scaffold with a per-slug collision guard does not enforce the order (scaffold a second apart, list, pin with `strcmp`, or fix the helper per ORDERED_SCAFFOLD_TIMESTAMPS); snapshot vs join is the owner's call with NULL's meaning on the copy; a backfill whose source is populated after the migration is an operator statement, not a stem (the affected-rows count is fleet-wide); "endpoint-scoped" is a claim about the guard's callers — a guard in a shared loader is loader-wide; a walk's cleanup names its files and never glob-deletes tracked placeholders
- [references/ORDERED_SCAFFOLD_TIMESTAMPS.md](references/ORDERED_SCAFFOLD_TIMESTAMPS.md) — load when a plan touches a helper that stamps generated artifacts (migration stems, seeds, patches) with a timestamp prefix whose lexical order is the apply order, or scaffolds two such artifacts whose order matters. `now` plus an exact-path guard lets two scaffolds in one second (or a skewed stem, or a DST fall-back) apply in slug order. The fix is `max(now, greatest prefix on disk + 1 unit)` over every file owning a prefix, with the directory as the only state. Rules: calendar arithmetic in UTC; a round trip, not a `false` return, to validate a parser that silently normalises; parse only a prefix that can win; announce the bump, don't refuse it; describe the remaining path guard accurately; one discriminating test per wrong design.
- [skills/idea/references/IDEAS_LOCATION_STATUS.md](../idea/references/IDEAS_LOCATION_STATUS.md) — the location-by-status contract driving step 6's `idea` → `in-progress` move
- [docs/guides/SPRINT_WORKFLOW.md](../../docs/guides/SPRINT_WORKFLOW.md) — full sprint-workflow explainer with authoritative schemas
- [skills/idea/SKILL.md](../idea/SKILL.md) — previous stage; produces the IDEA file this skill consumes
- [skills/work/SKILL.md](../work/SKILL.md) — next stage; executes the plan this skill emits
- [agents/AGENT_architect.md](../../agents/AGENT_architect.md) — the reviewer persona invoked in step 5
