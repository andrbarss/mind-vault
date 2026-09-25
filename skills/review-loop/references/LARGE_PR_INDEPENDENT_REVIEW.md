# Large-PR escalation — don't trust a single fast-bot clean pass

A fast review engine (Bugbot / Copilot) that returns **CLEAN on a very large PR in a single pass** is
a weak signal, not a strong one. Fast bots sample and summarize; on a diff spanning dozens of commits
and thousands of changed lines, a one-shot clean verdict can mean "reviewed shallowly and found
nothing obvious" rather than "reviewed thoroughly and it's sound." Treat a large-PR clean pass as
*necessary but not sufficient*.

## When to escalate to an independent deep review

Heuristic threshold (tune per project): the PR is **large** when it crosses roughly any of —

- **≥ ~25 commits**, or
- **≥ ~2,000 net changed lines**, or
- it touches a **high-blast-radius surface** (WebSocket/streaming lifecycle, auth/permission gates,
  embed/security model, a monolithic file with hardcoded DOM ids, schema/migration).

When a large PR gets a single-engine clean pass (or one engine cleared and the other errored/was
shelved), escalate: dispatch an **independent deep reviewer** on the net PR diff
(`git diff <base>...HEAD` — three-dot = merge-base diff, review the final state, not each commit).

## Two distinct lenses (run in parallel, non-overlapping mandates)

Splitting the review by lens avoids redundant token spend and gives broader coverage than one
reviewer doing everything:

1. **Correctness / security** (a dedicated code-review subagent) — line-level bugs, logic errors,
   races, security vulnerabilities, regressions. Confidence-filtered: high-priority real issues only.
   Point it at the high-blast-radius areas explicitly.
2. **Architecture / convention / doc-accuracy** (a curator / architecture subagent) — dead or
   half-wired code (especially around anything *descoped* to a follow-up), convention adherence,
   rename-before-drop / hardcoded-id risk, and whether reference docs match the shipped code (decisive
   when the same PR rewrote docs).

Each returns a structured findings report (file:line + why-it's-real + suggested fix) and is asked to
state explicitly when a high-risk area is *clean* — silence isn't confirmation; an explicit
"checked X, clean" is. Then triage the findings through the normal loop tiers (auto-fix / approve /
escalate) and fold the fixes into the PR before merge.

## Why this earns its cost (observed)

On one ~50-commit / ~8k-line surface-migration PR a fast bot cleared in one pass, the independent
two-lens review surfaced three real items the bot missed: a teardown handler that left one socket
callback attached (stale-callback race on the next re-mount), a fragment endpoint that leaked record
existence via a 403-vs-404 distinction (vs the leak-resistant single-query-404 a sibling endpoint
already used), and a never-wired skeleton function whose docstring described it as live
infrastructure. None were style nits; all three were worth fixing before merge. The lesson: the cost
of two subagent reviews is far smaller than the cost of shipping a real bug a shallow pass waved
through on a big diff.

A second large-PR data point (a ~25-commit / ~7k-line shell-migration PR) sharpens the lesson from
"one bot" to "the whole automated gate": across a 3-engine loop (bugbot + copilot + claude), the engines
plus the user's hands-on smoke surfaced ~13 real issues — a stored-XSS replicated across **9** views, a
privilege-escalation via scope-change on edit, a permission denial returning 200 instead of 403, three
GET-render permission gaps, a TOCTOU create race, i18n extraction misses — none of which any single
engine's first clean pass caught. Two compounding traps showed up: (1) one fast engine reading CLEAN
while siblings still had findings — **a single engine's clean is not the gate's clean** (wait for the
slowest, batch all engines; see [`multi-engine-sync.md`](multi-engine-sync.md)); and (2) an engine whose
findings were **adapter-invisible** — claude posted convention findings in its summary-comment body that
the adapter didn't parse, so the loop read CLEAN while claude had flagged ~30 real items (the C1 fix in
[`engine-claude.md`](engine-claude.md) § calibration update — findings live in the SUMMARY BODY). The takeaway: on a large PR, treat
*every* engine's clean as provisional until (a) all engines agree on the same SHA AND (b) you've
confirmed the adapter actually surfaces that engine's finding shape — then still do the independent pass.

## Relationship to the loop

This is a **hand-back-time escalation**, not a replacement for the engine loop. Run the normal
`/review-loop` first; when it hands back CLEAN on a PR that meets the large-PR threshold, do the
independent pass before declaring the PR merge-ready. The independent findings re-enter the loop as a
fresh fix cycle (commit → push → re-trigger engines on the new SHA), so the engines still get a final
look at the fixes.

**Launching the lenses in parallel with the engine's run on the same SHA is fine**, and saves a whole
wait: give both lenses read-only instructions (`git show` / `git diff` only, no checkout, no test runs,
no database), then batch their findings with the engine's verdict into one fix cycle. Field case: the
engine posted a clean summary while the lenses found six real defects on the same SHA — a non-UTF-8
input echoed into an error body that then failed to encode (a 500), an uncapped id list past the
database's placeholder limit (a 500), a duplicate-key error escaping under a non-default isolation
level, a deadlock inside a caller's transaction reported as "saved", an error message blaming the
wrong record, and a leading-zero id silently ignored — plus a stale mirrored contract and a test sweep
that missed a parked table.

## The threshold is a floor, not a gate — a mid-size money-path PR earned the pass too

A second field case moves the trigger: an 11-commit / ~1.2k-line PR (well under both numeric
thresholds) that added one public money field to a coupon-sales API got an engine CLEAN, then the
user asked for the two lenses anyway. Correctness found a **MEDIUM** the engine and the author had both
missed — a numeric-string gate that let `1e999` through as an infinite price all the way to the INSERT
— and the convention lens found three **MEDIUM** gaps: a spec pin the plan had ticked but never written,
a committed capture carrying double-encoded UTF-8 from a latin1 seed session (invisible to the CLI
read-back the guide was transcribed from), and a migration missing from the migrations index; plus five
low doc / comment items. One fix commit, one engine re-run, CLEAN again.

So add a **surface trigger** alongside the size thresholds: run the pass on any PR that adds or changes
a **public money field** (price, amount, quantity, discount), a **write gate** (validation, refusal
table) or a **capture-backed spec** — regardless of commit count. The lenses cost two background
agents; the miss costs a coupon sold for `INF`.

## Run it while the engine runs — and let the doc lens read instructions as code

A third field case (~1.5k lines, 8 commits: a security-relevant setting got a second, admin-writable
source) adds two things.

**Timing.** The pass does not have to wait for hand-back. The engine's first full review takes minutes;
dispatch both lenses the moment the PR is marked ready and triage everything together — one fix commit,
one re-review. The trigger here was neither size nor money but **where a credential goes**: add "decides
who receives a secret / who is trusted" to the surface triggers above.

**What the doc lens is for.** The engine read CLEAN on the first pass and on the re-review; the
correctness lens found nothing above minor (and extended the author's exhaustive one-byte sweep to two
bytes). The only major finding was **a sentence in the operator runbook**: a human security check framed
as "before enabling the setting on a tenant" when the exposure began at the *code deploy* — a legacy
writer could create the row itself, and the same request consumed it. No test reads prose, and an engine
reviewing a diff has no reason to open the legacy controller the sentence was about. Prompt the doc lens
accordingly:

- for every **gate, precondition or ordering instruction** ("before X, check Y"): *where does the exposure
  actually start?* Follow the writers, not the feature;
- "would an operator following this page **without reading the code** reach a wrong state?" — name the
  sections most likely to mislead (precedence, kill switch, deploy order);
- every "never / only / nothing / always" is a claim to falsify, and a claim about **another repository**
  is a claim about a root nobody searched until someone opens it (both lenses repeated one such sentence
  here; a single `grep` in the sibling repository overturned it after the merge).

Give **both** lenses the exact container command for the suite. One reviewer had it and re-ran the touched
classes; the other tried the working tree's own dependencies, could not run anything, and had to verify
counts by reading test sources.

## "Read-only" in a reviewer prompt must name the generators

A lens told only "READ-ONLY: do not edit, stage, commit or push" ran the project's spec generator
while checking a description's length — the command rewrites a committed artefact. The output was
byte-identical, so nothing was lost; on a day the annotations and the artefact had drifted, the
reviewer would have silently "fixed" the very drift it was there to report, in the orchestrator's
working tree, mid-loop.

Name the project's writers in the prompt: *do not run* the spec / client / lockfile generators,
formatters with write flags, migrations, or anything that makes HTTP or DB writes — and list what
**is** allowed (the diff, `git show`, the test runner with a filter, small interpreter one-liners).
Ask the reviewer to declare any file it created outside the repo. After the lenses return, a
`git status` on the tracked tree is the orchestrator's own check before it starts editing.

## Review the fix increment too — fixes regress, and rewordings stay inexact

A third field case (a ~4k-line PR adding a bulk write API over a shared legacy table; engine CLEAN on
the head, then both lenses launched in parallel on the same SHA) adds a step *after* the fix commit.
The lenses found no high-severity defect but twelve real items (three medium, nine low) the engine had passed — a size cap
documented as running before the body is read while the read was evaluated as a function argument
first, error labels that echoed client-sized text once per problem, a negative pin that covered the
two controller actions but not the class holding the messages, and API text claiming "every item is
evaluated, nothing short-circuits" over a staged validator. One fix commit closed them.

An **independent review of that increment** (`git diff <reviewed-sha>..HEAD`, read-only, given the
findings table and asked two questions per claimed fix — *does it do what the table says? did it
break or contradict anything else?*) then found seven more: the label clipping had made key-only
messages **ambiguous** for two keys sharing a prefix (a regression of the fix), the reworded
sentence was *still* inexact (a value reports only its first broken rule), the widened pin covered
three of four gateway methods, a doc quoted a variable name the code and the pin did not use, and
the review write-up itself overstated the original exposure. The engine re-reviewed that fix commit
in full and read CLEAN on it as well.

So, on a large PR: **batch → fix → review the increment → fix → stop.** The second pass is cheap
(the diff is small and the reviewer is told exactly what each change claims) and it is where
fix-induced regressions and "corrected" documentation that is still wrong are caught. Stop after
it: a third pass over a wording-only increment is the cosmetic non-convergence of
[`COSMETIC_NONCONVERGENCE.md`](COSMETIC_NONCONVERGENCE.md). Give the docs-only wrap commit the same
single pass when the engine skips it — that one caught a verification guide still asserting the
opposite of what the README and the devlog (correctly) said about which commits the engine had
reviewed.

## Fresh reviewers, no prior findings — and what a third recurrence means

A fourth field case (a mid-size PR: a validator for an operator-written URL list whose accepted entries
receive a fleet-wide credential, plus a fan-out through a shared queue). The engine's first full review
raised one archive-layout finding and **called the rejected-entry log rendering safe**. The two lenses
found it leaked; the increment review found the fix leaked differently; the confirmation pass found the
second fix leaked a third way. Three things to take from it:

- **The same defect class a third time is a design signal, not a fourth fix.** This is not the
  cosmetic non-convergence of [`COSMETIC_NONCONVERGENCE.md`](COSMETIC_NONCONVERGENCE.md) — each finding
  was a real leak — so "stop" is the wrong answer and so is "patch again". Track recurrences per
  *category* in the loop's scratch file; at the second, write down what the third will trigger; at the
  third, remove the class (there: render nothing of a rejected entry, and stop returning the text from
  the validator at all). The fix after that needed no confirmation round, because there was no filter
  left to get wrong.
- **After the engine reads CLEAN, a review by reviewers who were given the contract but none of the
  findings still pays.** Asked for by the owner on the final head, two fresh lenses found what three
  rounds of increment review could not, because increment reviewers inherit the frame of what was
  already looked at: an entry point (one CLI script on one queue adapter) where the fan-out would
  silently never run, a repair the validator still performed, a cleartext rule whose rationale failed
  for an internal primary, and two operator-doc statements that were false by the code ("nothing resets
  a stale claim" — a reset action existed and was documented elsewhere in the repo). Give fresh
  reviewers the **contract** (numbered, testable) and the entry points; withhold the history.
- **Send the fix for a finding back to the reviewer who raised it**, as a bounded confirmation pass with
  the changes mapped to their finding numbers. It converged MEDIUM → LOW → clean, and surfaced a
  runtime-version difference the author's own runtime could not show. A reviewer probing on a newer
  runtime than production gives leads, not results — re-run the row on the production image.

Calibration for the push-triggered engine in that PR: of nine runs after the PR left draft, three were
full reviews and six were ~2-minute skips, including the docs-only wrap push and its fix — every
finding that changed the code came from the independent passes.

## The engine passed a guard the framework had made unobservable — and three claims about other repositories

A fifth field case (a mid-size PR: one validated column on a legacy admin save, a degrade ladder for
tenants the migration has not reached, a real-DDL fixture; engine CLEAN on the first full-diff run
after un-draft). The two lenses on the same SHA, launched while the engine ran:

- **Correctness found a dead guard the suite could not.** The strip that removes an empty key on an
  un-migrated tenant was built as `[$data, $this->refuse($data)]` — the array literal copies `$data`
  before the by-reference `unset()` runs. Every HTTP row stayed green, three of them with the column
  genuinely absent, because the ORM drops an unknown column key from a mass-assign anyway: the
  observable had two producers and the surface could not distinguish them. The lens found it by
  driving the decision method directly with a schema double; the fix assigned first and pinned the
  payload at the guard's own return. Ask of every guard in a degrade ladder *what else produces the
  same observable if this were deleted* — if a framework internal does, the pin belongs at the guard.
- **The doc lens found three sentences false by other repositories**, none visible from the diff: the
  mirrored schema contract was one commit stale and called its owner's PR a draft after it had merged
  (`gh pr view` in the owner's repo); "the column's only writer" was false — a legacy admin in the
  owner's repo mass-assigns the same table (a grep there); a shared test trait named a sibling fixture
  as a verbatim copy that in fact typed its own DDL (a read of the file). Give the doc lens the sibling
  repositories and `git show` access; a negative about another repository is checked in that repository.
- **The increment review found only wording** (a test-list sentence the fix had made false; a "six
  methods" that were five plus a guard) and the loop stopped there — the wording rode the docs wrap
  commit rather than a third billed cycle.

Calibration for the push-triggered engine: CLEAN on the un-draft run (first full diff), CLEAN again on
the fix push *and* on the explicit retrigger, which also confirmed the fix by name. Every finding that
changed the code came from the independent pass.

## Sending a stored flag outward: the engine read each call alone

A sixth field case (a mid-size PR sending a stored consent flag to an external system on three
calls). The engine was CLEAN on three full reviews. The two lenses, run while the engine ran and
again on the fix increment, found three MEDIUM consent-sync defects, and **each lived between two
calls, not inside one**:
- the booking copy and the person copy of the same answer fed different calls, so a withdrawal at
  check-in was undone by the next booking update;
- an admin edit wrote only the booking copy;
- a multi-booking cart kept a stale answer on the sibling.

The engine reviewed each call site correctly in isolation. For a PR that pushes one value through
several outbound calls, tell the correctness lens to draw the value's **sources × calls** table and
ask whether any two calls can disagree. See `skills/plan/references/LOCAL_FLAG_INTO_AN_EXTERNAL_RECORD.md`.

