# Architect reviewer-pass handoff

How `/plan` invokes `AGENT_architect` as a reviewer over a drafted plan, and how it integrates the findings. Load this file on demand at step 5 of the plan skill.

## Why architect is a reviewer, not an author

`AGENT_architect`'s 4-pass workflow — abstraction/genericity sweep, coupling/dependency probe, boundary contradiction analysis, deployment/scaling pre-check — is shaped around reviewing an existing design, not generating one. Using it as author would degrade both: the plan becomes a verdict document, the architect's review loses its independent read.

Plan drafts the design; architect reviews it. Two distinct passes, two distinct outputs.

## When to invoke the reviewer

- **Required for medium and large plans** (see "Right-sizing" in `SKILL.md`).
- **Optional for small plans** if the scope touches coupling, abstraction boundaries, or cross-cutting concerns.
- **Skip for trivial plans** — architect review is over-engineering for a one-file fix.

## Invocation protocol

Use the Agent tool to spawn a subagent with `subagent_type: mv-architect` (if available in the host) or invoke the persona inline from `agents/AGENT_architect.md`.

Prompt shape:

```text
You are AGENT_architect (see mind-vault/agents/AGENT_architect.md).

Review the drafted plan at <absolute-path-to-plan-draft>.

Run all four passes. Deliver the verdict in the structured ADR format from your
prime directives. Do NOT modify the plan file — findings go into your response
only.

Context:
- IDEA source: <path-to-IDEA-file or "none">
- Project: <project-name>
- Scope class: <small | medium | large>
```

Pass absolute paths. Do not inline the plan's contents — architect reads the file itself.

## Integrating the verdict

Architect returns one of three verdicts:

| Verdict | Integration action |
| --- | --- |
| 🟢 ARCHITECTURALLY SOUND | Mark the plan `status: ready`. Note the reviewer pass in the plan's Open Questions section as "Architect-reviewed 2026-04-19 — no findings." |
| 🟡 REQUIRES ABSTRACTION | Add each architect finding to the plan's Open Questions section with a recommended resolution. Revise the plan body (decisions, execution sequence) to reflect the required abstractions. Re-run architect review if the revision is substantial. |
| 🔴 REJECTED | Stop. The plan has a fundamental structural flaw. Return to the thin-input bootstrap or discuss with the user before re-drafting. Do not proceed to `/work`. |

## What architect is looking for

From `agents/AGENT_architect.md`:

- **Abstraction and genericity.** One-off hack or reusable pattern? If generic, belongs in `mind-vault/skills/` before being used.
- **Coupling and dependency.** Does frontend manipulate ORM directly? Tight coupling → isolation boundaries enforced.
- **Boundary contradictions.** Record deletion vs. attached CMS metadata — where are the fallback contracts?
- **Horizontal scalability.** Can it run on 5 load-balanced instances, or is state trapped in local sqlite / in-memory?

These are structural, not stylistic. If the plan passes architect but has, say, N+1 query risks, that's for `/<engine>-loop` in the review stage, not here.

## Docs-only plans still get the review — recalibrated to claim-vs-code verification

A documentation-only plan (CLAUDE.md authoring, reference-doc baseline, architecture write-up) looks like it has no architecture to review, so the temptation is to skip the reviewer pass for it. Don't. Recalibrate the four passes instead — and say so explicitly in the handoff prompt:

1. **Abstraction sweep → doc-structure drift check.** Where will the docs duplicate a machine-readable source of truth (column lists from migrations, route tables, command inventories)? Require each duplicated table to be stamped with its source ("as of `<migration>`", "regenerate via `<command>`") so staleness is detectable.
2. **Coupling probe → claim-vs-code verification.** The architect spot-checks every factual claim the plan makes about the codebase against the actual source files. This is the highest-yield pass: plans summarize a repo scan, and summaries are where wrong beliefs crystallize.
3. **Boundary analysis → what the docs commit future work to.** A wrong claim in a reference doc quietly locks future agents into a wrong architectural belief (the field-observed class: "X is only a dev dependency" when X actually ships at runtime — making a future "remove X" look trivially safe when it isn't).
4. **Scaling pre-check** — usually N/A; skip without ceremony.

Field calibration for why this pays: a docs-baseline plan for a small MVC app came back 🟢 sound but with four major claim-vs-code corrections — a CSS framework believed dev-only that actually shipped on every page; a documented localization invariant already violated by hardcoded strings in the code; a load-bearing route-declaration ordering the how-to guide had to name explicitly; a hand-rolled soft delete with no global query scope whose failure mode (silent data leakage on any forgotten filter) the docs originally wouldn't have mentioned. Every one would have shipped as confidently wrong documentation. Wrong docs are worse than no docs — downstream agents trust and propagate them without re-verifying.

Handoff-prompt addition for docs-only plans: "This is a documentation-only plan — calibrate the passes to claim-vs-code verification: spot-check the plan's factual claims against the referenced source files, check the planned doc structure for duplicated facts that will drift, and flag any claim that would quietly commit future work to a wrong architectural belief."

## What NOT to pass to architect

- **The IDEA file alone.** Architect reviews plans, not ideas. If the plan hasn't been drafted, there's nothing for architect to do.
- **A plan that is still in bootstrap mode.** Thin-input bootstrap must complete first.
- **Plans without explicit file paths in the execution sequence.** Architect will reject for lack of tractable review surface; draft a real plan first.

## When architect is unavailable

If the host doesn't expose subagent dispatch, or `agents/AGENT_architect.md` isn't loaded:

1. Load `agents/AGENT_architect.md` as a reference read.
2. Apply the four passes inline, documenting findings in the plan's Open Questions.
3. Note in the plan: "Architect pass applied inline — lack of independent reviewer is a risk on this plan."

Do not skip the review for medium+large plans. Inline-applied is acceptable; unreviewed is not.

## Architect amendments can be imprecisely-phrased — separate intent from mechanics

Architect amendments to a drafted plan sometimes pair a CORRECT structural intent with a WRONG-DERIVED consequent mechanic. The intent describes *what invariant must hold*; the mechanic describes *where in the code to put a particular construct to achieve it*. Field-observed example: "empty-state moves OUTSIDE the cotton so the inner items container is always present as the OOB swap target" — the structural intent ("items container always present") was correct and survived the implementation, but the consequent mechanic ("therefore empty-state must move outside") was wrong because the architect had conflated two swap targets (OOB pager wrapper vs. beforeend items container). Applying the mechanic verbatim shipped a regression that the manual-eval walk caught immediately.

**Discipline at `/work` time when consuming an architect amendment**:

1. Read the amendment twice. Identify the STRUCTURAL INTENT (the invariant the architect cares about) separately from the CONSEQUENT MECHANIC (where the code goes to achieve it).
2. Ground-truth the mechanic against actual runtime behaviour — swap semantics, event firing order, DOM state after N iterations of the affected flow. Render-and-assert tests pin fragment shape but not multi-swap DOM state; that's where mechanics-derived-from-architect-intuition most commonly fail.
3. If the mechanic breaks something user-visible, **reinterpret the mechanic while preserving the structural intent**. Document the reinterpretation in the commit message ("Amendment A1 reinterpreted: items container still always present per intent, empty-state stays inside slot to preserve atomic-swap behaviour") so future readers see both the architect's verdict AND the implementation-time correction.

This isn't permission to ignore architect findings — the intent is load-bearing. It's permission to refine the mechanic when implementation-time evidence (manual eval, browser walk, integration-shape failure) contradicts the architect's derivation. The architect reviewed the plan against the codebase as understood at review time; implementation-time evidence is downstream of that and authoritative for mechanics.

When applying a reinterpretation, prefer to surface it back into mind-vault via `/compound` after the IDEA ships — both as a refinement to the relevant skill reference (the actual mechanic that worked) and, if the misderivation cluster recurs, as a sharper architect prompt for future similar reviews.
