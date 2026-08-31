# VERIFY_BOT_API_CLAIMS — a review bot can be confidently wrong about a framework API

Review bots (Claude Code Review, Copilot, Bugbot) generate findings from a training
distribution that favours the **mainstream** variant of a framework. When your project uses a
**non-default variant** — a different toolkit, a flavour, a fork, or a pinned version whose API
diverges from the popular one — a bot can emit a **confident, specific, and wrong** API claim:
"class X is the Classic name, use Y", "method Z was renamed", "this import path is for vN, use
the vN+1 path." Applying such a "fix" blind can introduce a real bug the bot's own check would
never have caught (it doesn't run your build).

This is **false-positive triage**, distinct from [`COSMETIC_NONCONVERGENCE.md`](COSMETIC_NONCONVERGENCE.md)
(a bot that won't stop flagging *cosmetic* nits) and from [`common-review-findings.md`](common-review-findings.md)
(the catalogue of findings bots flag *correctly*). Here the finding is **factually false** for your
codebase, and the correct loop action is to **refute with evidence, not apply**.

## The discipline

When a bot makes a framework-API claim (a symbol is "wrong", "should be X", "doesn't exist",
"was renamed"), **verify it against the installed package before touching code** — not against
memory, and not against the bot's confidence. Ground truth is the dependency tree on disk:
`node_modules/<pkg>/`, `vendor/`, the pinned site-packages, the actual `Ext.define(...)` /
`class ...` / `export ...` in the shipped source.

Two fast tells that the bot is wrong (either alone is suggestive; both together is conclusive):

1. **The current symbol IS defined in the installed package.** `grep -rn "Ext.define('Ext.grid.filters.Plugin'" node_modules/` finds it → the code under review is correct.
2. **The suggested replacement is NOT found anywhere.** `grep -rn "Ext.grid.plugin.GridFilters" node_modules/` returns nothing → the bot invented (or mis-remembered from another variant) a symbol that doesn't exist in your install. Applying it would break the loader/compiler.

The **empirical clincher**: if the code already runs clean in the real build/test (the feature
works, the plugin loads, no loader/import error), the "fix" is solving a problem that does not
exist. A green run against the real framework outranks a bot's static claim.

## Worked example (public framework — safe to cite)

A project on the Sencha **ExtJS Modern** toolkit (`"toolkit": "modern"`) had
`requires: ['Ext.grid.filters.Plugin']`. A review bot flagged it: *"that's the Classic class
name; Modern uses `Ext.grid.plugin.GridFilters`."* Both halves were false for that install:

- `Ext.grid.filters.Plugin` **is** the Modern class — `Ext.define('Ext.grid.filters.Plugin', …)`
  lives in `@sencha/ext-modern/src/grid/filters/Plugin.js` (alias `plugin.gridfilters`).
- `Ext.grid.plugin.GridFilters` **does not exist** anywhere in `@sencha/ext-modern` — applying
  the suggestion would have made the `requires` unresolvable and broken the dev loader.
- The e2e already ran clean in the real dev build with the plugin present and no loader error.

The bot reasoned from mainstream/Classic Ext knowledge; the project used Modern. The finding was
dismissed with an evidence-based rebuttal on the thread; **no code change**.

## The adjacent case: the finding is right but the suggestion is wrong

The sections above cover a bot whose **diagnosis** is false. The commoner and sneakier variant is
a bot whose diagnosis is **correct** while the concrete value in its ```suggestion``` block is
not. The finding earns your trust; the suggestion inherits it; the wrong number lands.

It happens because the two halves are produced differently. Diagnosis is *comparison* — "these
two documents disagree", which a bot does well from the diff alone. The replacement value is
*derivation* — the bot must compute the right answer, and it can only compute from what the diff
shows it.

Worked case (documentation PR, counts of a generated artefact). The bot correctly spotted that a
"N when this work started" figure was the **midpoint** rather than the baseline — genuinely wrong,
and diagnosed from the PR's own text. Its suggested replacement then derived the second figure as
`final − added`, which assumed the authoring change was the *only* contributor to that artefact
in the window. It was not: a sibling change had landed two more entries concurrently. The
diagnosis was right, the arithmetic was right, the **premise** was wrong, and applying the
suggestion verbatim would have replaced one incorrect number with another — while closing the
thread and making it look settled.

The bot had even hedged: *"verify the starting count before committing — if X is the net addition,
this is correct; if some were also removed or renamed, the other figure might be right."* That
hedge is the signal to read for.

**The discipline**: accept the *diagnosis* and the *suggestion* as two separate claims requiring
two separate verifications.

- Derive the correct value from **the source of truth, not from the diff** — for a count, read the
  artefact at the base commit rather than doing arithmetic on the PR's own numbers:
  `git show $(gh pr view <N> --json baseRefOid -q .baseRefOid):<path> | <count it>`.
- **Any hedge in the suggestion body** ("verify before committing", "assuming X", "if Y then Z")
  marks the half the bot could not verify. That is precisely the half to check.
- A one-file `suggestion` block that is *committable in one click* deserves more scrutiny than a
  prose finding, not less — the friction that would otherwise make you think is gone.
- When you take the diagnosis but not the suggestion, **say so on the thread** with the command
  that settles it, then resolve. It closes the loop honestly and stops the next cycle re-raising it.

## How it slots into the loop

- This is a **Tier-3 disagreement** with the engine, not a defect → it does **not** auto-clear to
  CLEAN, and you do **not** blindly apply the suggestion.
- **Post a refutation on the finding's thread** citing the installed-package evidence (file:line of
  the real definition, the empty grep for the suggested symbol, the green real-build run). This
  resolves the finding on the record and gives the human the proof.
- **Do not re-trigger the engine on unchanged code** to "clear" it — the same false positive
  reproduces and bills another cycle. Hand back to the human: *finding assessed as a verified false
  positive, evidence posted, no change*. The merge decision is theirs.
- If you're genuinely unsure after checking the installed package, treat it as a real finding and
  escalate to the human — the discipline is "verify", not "assume the bot is wrong."

## Why it's worth a standing reference

A bot's framework claims are highest-risk exactly where they feel most authoritative: a crisp
"use class Y instead of X" reads as a mechanical fix a tired operator applies without thinking.
The non-default-variant blind spot (Classic-vs-Modern, fork-vs-upstream, vN-vs-vN+1) is where the
bot's prior and your reality diverge — and it's invisible unless someone checks the dependency on
disk. Pairs with the general "verify, don't blindly implement" review-receiving stance; this is its
sharpest, most actionable instance.
