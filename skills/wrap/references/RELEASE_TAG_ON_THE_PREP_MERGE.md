# Tag the release-prep merge, not the default branch's tip

Load at `/wrap` Step 4b (and at any release hand-back) in a project where feature PRs merge **directly into the
default branch** and a release is a release-prep PR (version bump, dated changelog) followed by a tag that the deploy
tooling deploys. That is the usual shape after an integration branch (`dev`) is retired.

## Why

With an integration branch, `main` moves only when a release merges: `origin/main`'s tip *is* the release, so "tag
`origin/main`" is correct by construction. Retire the integration branch and that stops being true. Every feature PR
now lands on `main`, so between the release-prep merge and the moment someone runs the tag command, another PR can
merge. Tagging the tip then releases that PR as well:

- its changelog entry sits under `Unreleased`, not under the version that now ships it;
- a deploy tool that reads the changelog sections between the host's version and the target, pausing on their
  **Deploy** notes, never sees that PR's note;
- `VERSION` still reads correctly, so no check flags it.

The tag command in the release docs is the place where the old invariant hides. It keeps working, silently, after the
branch model changes underneath it. Field case: a project retired `dev`, rewrote its branch docs, and kept
`git tag -a v$(git show origin/main:VERSION) origin/main …` word for word. Only an independent review of the
workflow PR caught it.

## The rule

Tag **the release-prep PR's merge commit**, read from the PR itself, and push **only that tag**:

```bash
git fetch origin \
  && sha=$(gh pr view <prep-PR> --json mergeCommit -q .mergeCommit.oid) \
  && v=$(git show "$sha":VERSION) \
  && git tag -a "v$v" "$sha" -m "<project> v$v" \
  && git push origin "v$v"
```

- `git push origin --tags` pushes every local tag, including a stray experiment. Name the one tag.
- Read the version from the commit you tag (`git show "$sha":VERSION`), not from the tip.
- Update every place that prints the tag command: the release section of the dev docs, the deploy tool's
  "not tagged yet" refusal, the agent instructions (CLAUDE.md / AGENTS.md), and the `/wrap` hand-back.

## The other consequences of a main-only flow

When the branch model changes, re-read these too. Each assumed "`main` == the release":

- **"`VERSION` is the version of `main`"** becomes "the version of the last release; `main` may carry unreleased
  work". The running version is the newest tag.
- **Copy-from-the-repo fallbacks** (`git archive origin/main <paths>` to ship config files to a host) can ship files
  newer than the host's release. Archive the host's tag instead.
- **Changelog link references.** The new version's link points at the release-prep PR, whose number exists only once
  the PR is open. `[Unreleased]` changes from `compare/main...dev` to `compare/v<version>...main`.
- **CI triggers and branch rulesets** that list the retired branch are harmless but misleading; drop the branch.
  Check whether a required-checks ruleset existed only on the retired branch.

## Checklist

- [ ] The tag goes on the release-prep PR's merge commit (`gh pr view <N> --json mergeCommit`), and only that tag
      is pushed
- [ ] Every printed copy of the tag command is updated (docs, deploy refusal text, agent instructions)
- [ ] `VERSION` and the README describe the last release, not the tip
- [ ] File-copy fallbacks archive a tag, not the default branch
- [ ] The changelog's `[Unreleased]` and new-version link references follow the new flow
