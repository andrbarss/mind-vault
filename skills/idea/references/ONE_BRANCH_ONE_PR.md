# One branch, one PR per IDEA — capture, plan, code and wrap ride together

Load when `/idea` is about to open a branch or a PR, when `/work` decides what to branch from, or
when a reviewer meets a "stacked" pair and wonders which is the base. The default topology of the
sprint workflow is **one branch and one PR per IDEA**; the stacked docs-PR + code-PR pair is the
exception, kept documented because existing repos still carry a few.

## The default

```text
/idea   → git checkout -b feat/idea-NNN-<slug> origin/<default>   (docs/… when the IDEA is docs-only)
           commit the capture + index line; open ONE draft PR against the default branch
/plan   → commit the IDEA move + plan (+ contract) on the SAME branch
/work   → commit the code on the SAME branch (plan progress marks ride along)
/wrap   → docs finalisation on the SAME branch; /review-loop un-drafts and reviews the one PR
human   → merges the one PR
```

Branch from the **default** branch, never from another IDEA's branch. The `<type>` prefix follows
the IDEA's dominant deliverable (`feat`, `fix`, `docs`, `refactor`, `chore`); the slug is the IDEA's.
The PR stays **draft** until `/review-loop` un-drafts it (the push-triggered review engine bills a
review per push on a non-draft PR).

## Why not a docs PR with the code PR stacked on it

The pair looked attractive — the plan is reviewable before code exists, and the code PR's diff
stays free of planning prose — but in practice it cost more than it gave, every time:

- **Merge-order hazard.** Merging the *base* (docs) PR first orphans the child: both PRs read
  `MERGED`, yet the code never reaches the default branch. It has bitten once in the field and is
  invisible from every usual signal (see `RULE_git-safety` § 4).
- **Forward-sync twice.** Syncing the default branch into the pair means merging it into the docs
  branch, pushing, then merging the docs branch into the code branch, resolving and testing each
  step — and re-running `composer install`-style vendor repairs twice on repos that track vendor.
- **Two PR bodies to keep current**, two review histories, two merge clicks in a fixed order.
- **The docs PR often went un-reviewed.** Opened as a draft at capture time so the engine would not
  bill on every plan push, it then never got un-drafted before merge — the plan, the contract and
  the wrap prose shipped with zero engine eyes on them.
- **The one benefit is recoverable.** The plan is still visible in the single PR's commit history and
  in the archive dir; a reviewer who wants to read the plan first reads the plan commit.

A user who watched this play out on one IDEA decided: one PR per IDEA. This reference records the
default so no stage re-invents the pair.

## When a stacked pair still exists

Repos with in-flight stacked pairs keep the forward-sync discipline in
[`../../wrap/references/PRE_WRAP_FORWARD_SYNC.md`](../../wrap/references/PRE_WRAP_FORWARD_SYNC.md)
§ "Stacked PR pairs" (sync the base first, then the head; merge child → base → default). Do not
start new pairs; let the existing ones merge and the section becomes history.

## What each stage checks

- `/idea`: am I on the default branch? Then create the IDEA's branch and the one draft PR. Am I
  already on an IDEA branch? Then this capture belongs to *that* IDEA only if it is the same one;
  otherwise switch to the default branch first (worktrees keep this cheap).
- `/plan`, `/work`, `/wrap`: commit on the IDEA's branch; never `checkout -b` a second branch for the
  same IDEA (the post-merge wrap fallback `docs/idea-NNN-wrap` is the one legitimate exception — it
  exists because the IDEA's branch is already merged and gone).
- `/compound`: its own branch and PR, because its writes outlive the IDEA (solutions docs, mind-vault).
