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
