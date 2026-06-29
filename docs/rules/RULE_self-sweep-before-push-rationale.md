# RULE_self-sweep-before-push — Recipes, Detailed Sweeps, Rationale

## The Pyflakes Pipe Pattern

Most projects don't ship `pyflakes` in the production image. Two clean ways to run it on demand:

**Project Makefile target** (one-time setup, durable):

```make
self-sweep:
	@docker compose exec -T web pip install --quiet pyflakes 2>/dev/null
	@docker compose exec -T web python -m pyflakes $(PATHS)
```

**One-shot pip install + run** (when no Makefile target exists):

```bash
docker compose exec -T web pip install --quiet pyflakes
docker compose exec -T web python -m pyflakes <changed-files>
```

The pip install is idempotent (no-op if already installed) and free in any reasonable dev image — the marginal cost is ~50ms after the first run.

## Contract-Change Sweep — Full Recipe

Whenever you change a public-facing function's return type, parameter signature, or thrown exceptions, grep for ALL callers in the SAME commit.

The single most common "wasted review-bot cycle" pattern this prevents: a helper changes its contract, you patch the obvious caller, ship it. Bot spots a second caller — often in the SAME file. You fix that, ship. Bot spots a third caller in another file. Three cycles burned on what was one self-contained refactor.

### The grep that catches it

```bash
# JS/TS/Python helper rename:
grep -rn '\bfunctionName(' --include="*.js" --include="*.ts" --include="*.py" .

# Python method on a class:
grep -rn '\.methodName(' --include="*.py" .
```

Run from the project root, not the file's directory — the bot's review scope is the whole repo, so the sweep must match. The trailing `.` is mandatory: without a path operand, GNU `grep` reads stdin and appears to hang. (If you prefer `rg`, the directory defaults to the current working dir, so the trailing `.` isn't needed.)

### What counts as a contract change worth sweeping

- **Return type changes**: `return undefined` → `return Promise.reject(...)` (any sync→async). Callers without `.catch()` leak unhandled rejections; without `await` they see different behaviour.
- **Throwing where the caller didn't expect**: previously infallible function now raises. Wrap-checking callers crash.
- **Default parameter changes**: previously optional positional now required. Silent regressions everywhere.
- **Async-ifying a sync function**: callers that ignored the return value silently complete out-of-order; races appear intermittently.
- **Removing a side effect**: callers depending on DOM mutation, log emission, cache invalidation silently degrade.

### What does NOT need the sweep

- Pure additions: new optional kwarg, new return field on a dict. Callers ignoring the new surface are unaffected.
- Internal refactors that don't cross the function boundary.
- Adding logging / metrics that don't alter return value or exception shape.

### When the sweep finds many callers

- **All in one file or tight cluster**: handle in the same commit. One atomic diff.
- **Spread across many files / apps**: ship contract change in commit N with backwards-compat shim (returns both old AND new shape); ship per-caller updates in N+1...N+M; remove shim in N+M+1. The shim window prevents an N-file PR blocking on per-file review feedback.

## Defensive-Code Sweep — Full Recipe

When you add a defensive path that READS a field, grep for the WRITE site in the producer code BEFORE shipping the defense. Zero writes = phantom-field guard whose condition is permanently `undefined`.

Failure mode: `if (state.someField)` reads a field that was renamed, never existed, or lives on a different object. The guard *appears* to work — the field is always falsy, so the defensive branch always fires. Its "recovery" (reload, retry, fallback) masks the real bug. Invisible during manual smoke; surfaces only when the defense is later investigated for retirement.

### The grep that catches it

```bash
grep -rn '\b<fieldName>\s*=' <producer-module>/   # assignment
grep -rn '\b<fieldName>\b' <producer-module>/     # widen if assignment uses computed keys
```

For JS module-level stores / Alpine stores / class instances:

```bash
grep -B 2 -A 20 'Alpine.store(.<storeName>' <module>/static/<module>/js/
```

Read every key in the literal. If the field isn't there (and isn't ASSIGNED in any code path), the field doesn't exist — find the correct key or remove the defense.

### When this sweep especially matters

- Any `try`/`catch` whose `try` body reads a field you didn't author (catch silently swallows `TypeError: Cannot read property X of undefined`).
- `if (obj.field)` guards where `obj` comes from a different module / store / library.
- Refactoring a producer that renames internal fields — every consumer's defensive guard now reads a stale name.
- Diagnostic logging that reads state from another module — if `frames` was renamed to `stack`, `console.log('frames:', store.frames)` always prints `undefined` and the diagnostic appears to confirm the field is "empty" when it doesn't exist.

## Touched-Suite Sweep — Full Rationale

Whenever you run a test suite and observe pre-existing failures unrelated to your change, FIX THEM in the same PR. The cost: 5-30 minutes per failure once diagnosed. The benefit: compounds.

### When this fires

- `make test` to verify YOUR change, report shows N failures, M were already failing on parent.
- Forward-merge of an upstream branch surfaces failures invisible when the upstream PR landed.
- A bot review reports findings on tests already failing — bot doesn't distinguish "your fault" and neither should you.

### The rule

If suite reports M pre-existing + N new failures:

1. Triage all M+N together. Don't draw "mine vs theirs" boundary.
2. Identify actual cause per failure (source, test, commit that introduced the breakage).
3. Fix or update each test in the SAME PR. If EXPECTED constant was never updated after a related refactor, update it. If contract is genuinely obsolete, delete the test with explanation.
4. Commit message attributes the introducing change: "Pre-existing failures from IDEA-XXX refactor — EXPECTED constants weren't updated".

### Why this matters

- **Habituation**: known-failing tests train the team to ignore red. Next genuine regression hides behind the same dismissal.
- **Bisect-poisoning**: shipping with red tests means `git bisect` against future regression can't distinguish "this commit caused the failure" from "failure existed all along".
- **Reviewer confusion**: reviewer sees N failures, can't tell which are your responsibility. Either approves blind or asks you to attribute.
- **Compound interest**: every PR shipped with M pre-existing failures grows the noise floor by M. The dominant strategy if everyone follows the discipline is to monotonically decrease the count.

### Anti-pattern

❌ "These 4 failures are pre-existing — I'll file a follow-up issue."

The follow-up issue rarely ships (not attached to a feature cycle). Other engineers apply the same dismissal. Six months later the suite has 40 known-failing tests nobody trusts.

## Pipeline Exit-Code Discipline

The sweep is only as honest as the script that runs it. A pipeline whose **upstream** stage fails but whose **downstream** stage exits 0 will tell you "success" when the actual sweep / build / test never ran. The canonical bite:

```bash
./tools/sprint-auto-bootstrap.sh integration-runner 0 --port-offset 30000 \
    2>&1 | tee -a "$BATCH_LOG"; echo "=== BOOTSTRAP EXIT: $? ==="
# Prints "BOOTSTRAP EXIT: 0" regardless of the bootstrap's actual exit code,
# because $? captures `tee`'s exit, not the bootstrap's.
```

`tee` (and `cat`, `head`, `tail`, `jq` reading a pipe, almost anything downstream of `|`) is essentially-always going to exit 0 — so anything `$?` could tell you about the upstream is gone. **Cost of getting this wrong**: shipping a "bootstrap green" status to a downstream step that actually failed at the very first `sed`, then watching the next step trip over the absence of the artefacts the bootstrap was supposed to produce — a wasted iteration in a review-loop budget.

Two equally-clean fixes; pick whichever fits the call site:

1. **Drop the pipe** — `./script ... > "$LOG" 2>&1; echo "EXIT: $?"`. The script writes directly to the log; `$?` is now the script's exit. Simplest when you don't need progressive stdout.
2. **`PIPESTATUS[0]`** — `./script ... 2>&1 | tee -a "$LOG"; echo "EXIT: ${PIPESTATUS[0]}"`. Bash-specific; reads the exit code of the first command in the most recent pipeline. Keep this when you genuinely want `tee` (live progress + retained log).

Either form is one keystroke past the buggy form and removes the lie.

The same shape bites less obviously in:

- `make test 2>&1 | grep -E 'PASS|FAIL'; echo "$?"` — `grep`'s exit (0 = found, 1 = no match), not `make test`'s.
- `pytest ... | tee artifacts/pytest.log` in CI scripts where the job's pass/fail is keyed off `$?`.
- `gh api ... | jq '...'` where a 404 from the API gets formatted as `null` and the job continues.

**The discipline**: when a script's purpose is to **gate** a subsequent step (commit, push, retrigger, hand-off), the exit code that gates MUST be the upstream's, not a downstream filter's. Prefer redirection over `tee` unless live progress is genuinely required; when `tee` is required, use `${PIPESTATUS[0]}`. Adding the word "bootstrap" or "test" to the eventual "EXIT: 0" output doesn't make the 0 honest — name the source, not the destination.

## Scope: Touched Files, Not Just New Edits

When pyflakes flags pre-existing dead imports / unused locals in a file you're editing, clean them up in the same commit (or a `chore(tests):` commit if the diff would otherwise be confusing). Pre-existing findings in touched files are in scope.

**Threshold**: ≤ ~10 mechanical edits → roll into the current PR. > 10 → separate cleanup PR.

## Why This Matters — Top-Level

### The review-bot-cycle math

A bot takes 3-10 minutes per review cycle: comment posted → fetch via API → triage → apply fix → push → re-review. A 1-second pyflakes sweep that catches the same finding eliminates that cycle entirely. For a multi-cycle review-loop on a single PR, every avoided cycle compounds: wall-clock + context-window cost + bot billing.

### Trivial findings dominate the no-progress-loop budget

The review-loop's no-progress detector treats every category-attempt as a budget hit. A trivial dead-import finding consumes the same per-category counter as a substantive bug.

### "Is this commit obviously sloppy" — not "perfectly clean"

Full ruff / mypy passes are PR-time / CI-time concerns. The sweep is the minimum bar.

## Anti-Patterns

- ❌ "It'll get caught in CI / by the bot eventually" — yes, and each catch is a 3-10 min cycle. The sweep is 1 second.
- ❌ Skip-on-pre-existing — if the file has 5 dead imports and you add a 6th, fixing only the 6th leaves the file in the same state.
- ❌ Run pyflakes from inside an IDE that lints on save — sometimes works, sometimes doesn't, depends on Python interpreter resolution + venv config. Container-side run is authoritative.
- ❌ Suppress with `# noqa: F401` when the import is actually dead — masking, not fixing. Suppress only when the import has a side effect (e.g. registers a Django app's signal handlers).

## Doc-Consistency Sweep — Full Recipe

Doc-heavy commits (IDEA files, the ideas index/README, plan docs, dev logs) draw a predictable review-bot Info-finding class that is **entirely locally checkable**. Bots emit these **one nit per cycle**, and each cycle is a billed round-trip — so the cost is multiplicative in the number of latent nits, not additive. Sweeping all six checks locally before the *first* trigger collapses that to zero.

### The six checks

1. **Frontmatter ↔ body cross-ref symmetry.** Every id in a file's `related:` / `depends_on:` / `supersedes:` frontmatter should be discoverable in the body's prose, and every id discussed in the body's "Related" section should be in the frontmatter. When you *add* an edge in frontmatter (e.g. `related: [..., NNN]`), add the matching one-line backref in the body — bots flag the asymmetry. **Applies to every edge type, and to every id within a list** — a `depends_on: [A, B]` whose prose mentions only B is the exact asymmetry bots catch. Name all the ids the frontmatter lists, not just the one you were focused on.

2. **Ordering-block ↔ index/table membership.** Every entity named in a locked-order / sequence / recap block must have a corresponding row in any progress/index table the same doc maintains. A reorder that introduces an id into the chain without a table row is the classic miss. Mechanical check:
   ```bash
   # ids named in the ordering line vs ids with a table row — the diff is the gap
   grep -oE 'IDEA-[0-9]+|[0-9]{3}' <ordering-block> | sort -u > /tmp/in_order
   grep -oE '^\| [0-9]{3} ' <doc> | tr -dc '0-9\n' | sort -u > /tmp/in_table
   comm -23 /tmp/in_order /tmp/in_table   # named in order, missing a row
   ```

3. **Count / range claims vs the listed set.** Any "N-item cohort" or "(X→Y)" range phrasing must match what's actually enumerated below it. Adding an item outside the stated range silently invalidates the count — prefer "(IDs A–B, with gaps)" or drop the hard count entirely rather than maintain a brittle number.

4. **Domain-terminology precision.** Name the actual layer, not a plausible-sounding neighbour. Multi-tenancy example (django-tenants): a model that lives in a `SHARED_APPS` app is shared/public-schema — adding a field to it is a **shared-schema migration**, NOT a per-tenant one. "Per-tenant" describes data that *varies* per tenant, not the schema it physically lives in. Mis-scoped schema/auth/permission terminology is a favourite bot nit because it reads as a correctness risk.

5. **PR-description ↔ final-diff drift.** After a mid-PR reorder or a dependency-edge flip, the PR body written for the first commit goes stale. Re-read the PR description against the *final* diff before the next trigger — bots compare the two resources and flag conflicting guidance. A one-line "earlier draft said X; reversed in a follow-up — the diff below is authoritative" note also resolves it.

6. **Frontmatter formatting matches repo convention.** When a file is created from a template, strip the template's placeholder hint comments (`status: idea  # idea | in-progress | …`, gate-explanation comment blocks) before commit if the repo's existing files keep frontmatter comment-free. Mismatched frontmatter style is a low-cost bot nit. Quick check — compare the new file's comment count against a sibling:
   ```bash
   awk '/^---$/{c++;next} c==1 && /#/{n++} c==2{exit} END{print n+0}' <new-file>   # vs a sibling; should match
   ```

## Guard-Return-Asymmetry Sweep — Full Recipe

A *guard family* is a set of sibling methods implementing the same "is there anything to do here?" no-op decision across several backends — engines, adapters, providers, drivers, channels. They share a shape: `if (!active || empty($remoteHandle)) return <X>;` then do the real work. The trap is that **one member returns a different `<X>` than the rest** on the same empty-input branch — `false`/throw where the siblings return `true` (no-op success), or vice versa — and a *caller that gates a local side effect on the return* turns that single-token divergence into a silent data bug.

The canonical failure: a cancel/update/sync entry point gates its own local work on the guard's return —

```text
if (!$this->syncEnabled || $provider->guard($row)) {
    …commit the LOCAL effect (status change, row write, broadcast)…
} else {
    return error;   // "couldn't sync externally"
}
```

When `guard()` returns `true` on an empty remote handle (nothing registered externally → nothing to do → success), the local effect runs. When one provider's `guard()` returns `false` on that same empty handle, the gate inverts: the local effect is silently skipped and the row is stranded. Each method passes its own unit tests; each reads as locally sensible. The bug only exists *in the relationship* between the divergent sibling and the gating caller — which is why neither a single-file review nor a per-method test catches it.

### Why it hides

- **Per-file correctness.** Returning `false` when there's no remote handle is a defensible local choice ("I can't cancel what was never created"). It's only wrong relative to (a) its siblings and (b) the caller's gate semantics.
- **The empty-input branch is rarely exercised.** The handle is usually populated; the empty case is a newer/edge state (e.g. a deferred-registration row whose remote id hasn't been backfilled yet). Tests seeded with a populated handle never hit it.
- **Reviewers read the diff, not the family.** A diff that touches one provider doesn't surface the other six, so the asymmetry stays off-screen.

### The grep

When you touch or review any member of a guard family — or a caller that gates on one — line the whole family up and read the empty-input branch of each:

```bash
# 1. Find the family: every implementation of the guard method name
grep -rn 'function <guardName>' <providers-dir>/

# 2. Read each one's empty-input branch — what does it return when the
#    handle/id/key is absent? Build the truth table by hand:
#    provider        empty-handle return
#    ------------------------------------
#    A (first-probed) false   ← odd one out
#    B               true
#    C               true     ...
# 3. Find the gate(s): callers that branch on the return
grep -rn '<guardName>(' <callers-dir>/ | grep -E 'if *\(|\|\||&&|return'
```

The fix usually belongs at the **shared seam** the whole family routes through (a wrapper/dispatcher), not in each provider — one short-circuit (`if (!hasRemoteHandle($row)) return true;`) fixes every backend uniformly and can't drift. Per-member edits re-introduce the asymmetry risk on the next backend added. Pair with the *defensive-code sweep* (trigger 3): verify the field the short-circuit reads (`$row['remoteHandle']`) against the producer's write site.

### When this fires

- A bug fix that flips one guard's empty-input return — sweep the siblings so the fix is consistent, and decide wrapper-vs-per-member.
- A review of a diff that adds a new backend to an existing guard family — the new member must match the family's empty-input contract.
- Any "this works for engine X but not engine Y" report where the engines share a guard family — return-value asymmetry is the first hypothesis.

### Variant: state-finalization asymmetry (branch family + a shared write sink)

The return-value asymmetry above has a sibling shape that the same "line up the family" sweep catches — but the divergence is a **missing state-write**, not a divergent return, and the consumer is a **shared persistence sink**, not a gating caller.

The shape: a method has several `if/elseif` branches that each handle one mode (e.g. a `create()` with a synchronous-engine branch, a deferred-registration branch, and an alternate-engine branch), and they all converge on **one shared write line** downstream:

```text
if      ($syncEngine)   { … $row['id'] = $providerResult['localId'] ?? null; }   // finalizes
elseif  ($deferred)     { $row['deferMarker'] = 1; /* ← forgets to finalize $row['id'] */ }
elseif  ($altEngine)    { … $row['id'] = null; }                                  // finalizes
…
$data['id'] = $row['id'];   // the shared sink — reads whatever each branch left
```

Two of the three branches finalize `$row['id']` (the alt-engine one explicitly nulls it; the sync one takes it from the provider, legitimately nullable). The deferred branch **omits the finalization**, so the sink persists a *stale value carried in from earlier* in the method (a locally-searched id) — a **phantom** the mode was never supposed to keep. Downstream readers keyed on that field (an availability index that marks the phantom busy; a `WHERE field IS NULL` filter that now *excludes* the row from a deduction it should be in) silently corrupt — exactly the per-file-correct, only-wrong-in-the-relationship signature of the return-value case.

**Why it hides (same family logic, two extra wrinkles):**

- **The shared sink obscures the producer.** Every branch *looks* complete because the sink line is far below; you have to scroll all branches against the sink to see which one didn't set its share.
- **An aspirational comment masks the omission.** The killer wrinkle: the divergent branch often carries a comment that *claims the contract it never implements* — e.g. `// insert the row with id/handle unset (the unassigned case)` sitting directly above code that never unsets them. This is **not** trigger 1's *stale* comment (a comment that was once true and drifted); it's a **forward-looking comment describing intended-but-unwritten behaviour**. A reviewer who trusts the comment reads "id unset ✓" and moves on. The comment is the most dangerous part — it actively recruits the reviewer into missing the bug.

**The sweep:** when you touch one branch of such a family, line up *all* branches against the shared sink and build a finalization table — *for each branch, does it set every field the sink consumes?* The odd branch is the one with a blank cell. Then **read the code, not the comment**: if a comment claims a field is finalized, grep the branch for the actual assignment.

```bash
# 1. Find the shared sink (the line every branch feeds)
grep -n "data\['id'\] = " <file>          # the convergence point
# 2. For each branch above it, confirm the field is set; the divergent branch is the gap.
# 3. If a branch's comment claims the contract, verify the assignment exists — aspirational
#    comments lie. (comment says "X unset" ⇒ grep the branch for "X = null", not just trust it.)
```

The fix is usually one line in the divergent branch, mirroring a sibling (`$row['id'] = null;`) — and **refresh the lying comment** so it now matches (or, since it already described the intent, the code finally satisfies it). Pairs with trigger 3 (defensive-code): the downstream `WHERE field IS NULL` reader is a data-shape claim about what the producer writes — this variant is the producer side of that contract.

### When the state-write variant fires

- A bug fix in one branch of a multi-mode method (sync/deferred/alt-engine, create/update/import) where the branches share a downstream write — sweep the siblings for a missing finalization.
- Any "availability / dedup / filter is wrong only for mode X" report where mode X is one branch of such a family — a phantom/stale field from a missed finalization is the first hypothesis.
- A review of a diff whose comment says "with X unset / cleared / defaulted" — verify the code in that branch actually does it.

## Relationship to Other Rules

- [`RULE_git-safety`](../../rules/RULE_git-safety.md) — the sweep runs on the feature branch before push; doesn't change branch policy.
- [`RULE_rename-before-drop`](../../rules/RULE_rename-before-drop.md) — sweeps also catch leftover imports after a rename.
- The review-loop skill should run pyflakes self-sweep (triggers 1–4), the doc-consistency sweep (trigger 5), and the guard-return-asymmetry sweep (trigger 6) between Phase 2 and Phase 3 as a built-in step.
- Trigger 6 pairs with trigger 2 (contract-change) — both are about a method's return contract — and trigger 3 (defensive-code), which validates the field the recommended wrapper short-circuit reads.
