# A CONFLICTING PR gets zero `pull_request` workflow runs — check `mergeable` before blaming the engine

Field-observed 2026-08-25 on a downstream PHP project during a single-engine (`claude`) loop; the same
mechanism applies to every push-triggered engine that runs as a GitHub Actions `pull_request` workflow,
and to the project's own test workflow.

## The shape

1. Cycle 1 clears CLEAN on SHA₁.
2. Another PR merges into the base branch and touches the shared docs every IDEA edits (ideas index,
   devlog, README).
3. The loop pushes its fix commit SHA₂ (`synchronize`).
4. Nothing happens. `find_<engine>_comments.sh` reports **no check-run for the head SHA**; the finder's
   stale-summary guard fires; `gh run list` shows **no run for SHA₂ from any workflow** — the test
   workflow is silent too. A `close` + `reopen` (`reopened` is in the workflow's `types`) also produces
   nothing.

The tell is the *sibling* workflow: an engine can skip-no-op, but the plain test workflow has no reason
to. When **every** `pull_request` workflow is absent for the head SHA, the event is not reaching the
workflows at all.

## Why

GitHub runs `pull_request`-triggered workflows against the PR's **merge commit** (`refs/pull/N/merge`).
When the PR is `CONFLICTING`, that merge ref cannot be built, so **no `pull_request` workflow run is
created for any event** — `synchronize`, `reopened`, `ready_for_review` alike — and there is no failed
run, no check, no log to find. The absence is total and silent.

```bash
gh pr view <N> --json mergeable,mergeStateStatus --jq '"\(.mergeable) \(.mergeStateStatus)"'
# CONFLICTING DIRTY   → this is the cause; nothing engine-side will help
# MERGEABLE  CLEAN|UNSTABLE|BLOCKED → the engine really is the problem, continue triage
```

(`mergeable` is computed lazily and cached — re-query after a few seconds if it reads `UNKNOWN`.)

## What the loop must do

- **Phase 4 / zero-activity branch — pre-check before any retrigger.** When an engine is `NOT_TRIGGERED`
  for the head SHA *after a push that should have fired it*, run the `mergeable` query **first**. On
  `CONFLICTING`, do **not** fire `<engine>_retrigger.sh` (a mention-based retrigger runs on a different
  event and may be muzzled or deduped anyway; a `pull_request`-based one cannot run at all) and do not
  count the wake as an idle poll against HUNG — the engine is not hung, it was never invoked.
- **Fix = forward-sync the base branch on the feature branch**: `git merge origin/<base>`, resolve
  (shared-docs conflicts are keep-both in ship order — see the wrap skill's
  `PRE_WRAP_FORWARD_SYNC.md`), run the suite, push. The push that makes the PR `MERGEABLE` fires
  `synchronize` normally; every workflow runs immediately.
- **Record it**: `last_push_sha` moves to the merge commit; the engine state for the previous SHA is
  moot (it was never reviewed). Note the merge commit in the scratch cycle log so the hand-back can say
  which SHA the CLEAN verdict is for.
- **Do not `close`/`reopen` to "kick" a PR** — on a conflicting PR it does nothing, and on a mergeable
  one the plugin dedupes an already-reviewed SHA.

## Ordering lesson for the two-pass docs flow

The pre-review docs wrap edits exactly the files a sibling IDEA's wrap edits (ideas index, devlog,
README). If a sibling merges between the wrap push and the fix push, the loop's next push lands on a
conflicting PR. The wrap skill already forward-syncs *before* its edits; the review loop should treat
"base moved during my cycle" as a routine event, not an anomaly — one `mergeable` check per push-that-
fired-nothing is the whole cost.

## Related

- `engine-claude.md` § Stale summary on a new SHA — the finder flags the stale summary; this reference
  explains the one cause where the prescribed retrigger is wrong.
- `../../wrap/references/PRE_WRAP_FORWARD_SYNC.md` — the forward-sync mechanics and the keep-both
  resolution rule.
- `LARGE_PR_INDEPENDENT_REVIEW.md` — the independent-reviewer fallback that covered the unreviewed
  docs increment while the engine was blocked.
