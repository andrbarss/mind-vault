# Merged mid-loop — when a human merges while the review loop is still running

A human clicking **Merge** while `/review-loop` is mid-cycle does not abort the loop and does
not warn anybody. The loop keeps fixing findings and pushing; those pushes land on a branch
whose earlier state is already on the default branch. The result is a **partial merge**: the
default branch carries the feature *without* the hardening the review produced, and every
surface a session would normally check reads healthy.

This is not a rare race. It happens whenever a review cycle takes longer than the human's
patience — an independent-reviewer substitution, a slow engine, a multi-cycle fix loop.

## Why nothing catches it

Each signal, read on its own, says "done":

| Signal | Reads as | Actually |
| --- | --- | --- |
| `gh pr view <N> --json state` | `MERGED` | true, but of an **earlier commit** |
| `git status` on the branch | clean | true — the later commits are committed |
| `git log origin/<branch>` | shows every commit | true — they are pushed, just not merged |
| The loop's own scratch file | `last_push_sha` = branch tip | true, and irrelevant to what merged |

Nothing in that set compares **what merged** against **what exists**. That comparison is the
only detector.

## Detection — one command

The merge commit's **second parent** is the branch commit that actually merged. Compare it to
the branch tip:

```bash
# What did the merge actually capture?
git log <default> --merges --format='%H %P %s' -1        # 2nd parent = merged branch commit
git rev-parse origin/<feature-branch>                     # what exists

# Or, directly: is the branch tip on the default branch at all?
git merge-base --is-ancestor origin/<feature-branch> origin/<default> \
  && echo "fully merged" || echo "PARTIAL MERGE — commits stranded"

# And what exactly is missing:
git log --oneline origin/<default>..origin/<feature-branch>
git diff --stat origin/<default>...origin/<feature-branch>
```

Run this **before** declaring an IDEA shipped, and **first** when a post-merge state looks
wrong. `git branch -r --contains <sha>` is the cheap per-commit variant: if it lists only the
feature branch, that commit never reached the default branch.

## Recovery — measure the delta before proposing a revert

The instinct on discovering a partial merge is to revert and re-land cleanly. **Compute the
delta first.** In the field case that produced this document, the reflex looked right and was
wrong by an order of magnitude:

- Revert-and-re-land: **~1170 lines out of the default branch, then ~1170 back in**, plus a
  revert commit and a re-land PR in the history.
- Ship-the-delta: the missing commits were **9 files, +152/−31** — one small PR.

So:

1. `git diff --stat <default>...<branch>` — that is the whole remediation surface.
2. If the delta is small, open a PR from the **same branch** to the default branch. Because the
   merge-base is now the merged commit, that PR contains *exactly* the stranded commits — no
   cherry-picking, no re-application.
3. Revert only when the merged state is genuinely harmful on its own (a security regression, a
   broken build) and cannot wait for the follow-up PR. "The review wasn't finished" is not by
   itself a reason to revert — it is a reason to finish it.
4. If a revert PR was already opened, close it rather than merging once the delta is known to
   be small; say so on the PR so the history explains itself.

## Consequences worth checking after a partial merge

- **The default branch is running the pre-review state.** Whatever the review found is, by
  definition, still live. Read the findings again and judge urgency — a documentation-only
  finding can wait for the follow-up PR; a guessable-credential finding cannot.
- **A wrap that already ran wrapped the wrong thing.** If `/wrap` ran on the branch before the
  partial merge was noticed, its "what shipped" prose describes the full branch, not the
  merged subset. Re-check the devlog / index entries against what actually landed.
- **The archive's record needs the merge history**, not just the outcome. A future reader
  hitting a two-PR sequence in the log will assume it was planned unless the record says
  otherwise. One sentence — "PR A merged mid-review and captured commit X rather than the tip;
  PR B carries the remainder" — saves the re-derivation.

## Prevention

- **Keep the PR in draft until the loop hands back.** `/work` already opens PRs as draft, and
  `/review-loop`'s pre-flight is what un-drafts. A draft PR cannot be merged by an
  absent-minded click; that is a large part of why the draft default exists.
- **Say in the hand-back that the loop is still running**, and what a merge right now would
  strand. The human merging is not doing anything wrong — they are acting on the information
  visible to them, and "this PR has more commits coming" is usually not visible.
- **On resuming any post-merge work, verify the merge captured the tip** before building on
  the assumption that it did. It is one command, and every downstream conclusion depends on it.
