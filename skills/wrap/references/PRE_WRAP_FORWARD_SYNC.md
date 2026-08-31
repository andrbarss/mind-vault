# Pre-wrap forward-sync — merge the default branch before touching shared docs

Load at `/wrap` Step 1 (pre-merge mode) whenever other work may have merged to the default
branch since the feature branch was cut — i.e. almost always on a team or multi-session repo.

## Why

`/wrap` edits files that **every** IDEA edits: `docs/ideas/README.md`, the monthly devlog,
`CLAUDE.md` / `AGENTS.md`, the architecture doc, the CRUD/how-to guide. If a sibling IDEA
merged to the default branch while this one was in `/work` + `/review-loop`, the wrap commits
will conflict with it on exactly those files — and the conflict surfaces **after** the PR was
review-clean, at the moment the human clicks merge ("There is a conflict in Git"). Resolving
at that point is the worst time: the wrap commits are already pushed, the reviewer has already
read them, and the agent session that knew the context may be gone.

Field observation (2026-08-22, a Laravel project, two IDEAs in flight on parallel branches):
the default branch advanced **three times** during one IDEA's life — a CI-perms PR before
review, a sibling module PR before wrap, and that sibling's `/compound` docs PR after wrap.
Each one produced a GitHub `CONFLICTING` state on the open PR. All conflicts were additive
(both branches appended to the same list / table / sidebar array / lang map), i.e. trivially
resolvable — but only by someone holding both contexts.

## The rule

**Before Step 2 (frontmatter flip), fetch and forward-merge the default branch into the
feature branch; resolve; run the suite; commit the merge; then run the wrap steps on the
merged tree.**

```bash
git fetch origin
git log --oneline HEAD..origin/<default>          # anything new? if empty, skip the rest
git merge --no-edit origin/<default>              # feature tip moves; protected tip doesn't
# resolve — conflicts in index / devlog / CLAUDE.md / config maps are ALMOST ALWAYS "keep
# both sides, in ship order" (earlier-merged module first). Lint the result: PHP/py/JSON
# parsers catch the "kept both closing brackets" mistake immediately.
<test command>
git commit                                         # merge commit, then proceed with Step 2
```

Re-run the check **again right before hand-back** (after Step 6 patches are pushed): the
default branch may have moved during the wrap itself. `gh pr view <N> --json mergeable` shows
`CONFLICTING` when it has (the value is cached — re-query after a few seconds if it contradicts
`git merge-base --is-ancestor origin/<default> HEAD`).

This is forward-sync per `RULE_git-safety` (feature tip moves, protected tip doesn't) and is
always allowed.

## The second-order catch: a parallel module missed this IDEA's new convention

When the forward-merge brings in a **sibling module** that was authored while this IDEA was
introducing a **cross-cutting convention** (an audit-journal call every write action must make,
a mandatory service injection, a required lang key, a base class), the sibling is structurally
unaware of it — it was planned and reviewed against a tree that didn't have the convention yet.
Neither PR's review can catch this: each was correct against its own base.

So after the merge, **grep the incoming modules for the convention this IDEA added**:

```bash
git diff --name-only <merge-base> origin/<default> -- app/ src/ | sort -u   # what came in
grep -L '<convention marker>' <those controllers / modules>                 # who lacks it
```

Disposition — wrap is a docs pass, so **don't silently add the code here**. Record the gap in
the three places the wrap already writes (ideas-index summary with a ⚠️, devlog "Notes /
follow-ups", and the project's `CLAUDE.md` convention line as a "Known gap: <module> does
not … yet") and offer the user the ~4-line follow-up explicitly. The point is that the gap
becomes **visible** the moment the two branches meet, instead of being discovered when someone
wonders why module X never shows up in the audit log.

## Stacked PR pairs — sync the base branch first, then the head

When the feature PR is **stacked** on a docs PR (the idea + plan branch carries the archive dir
and the feature branch was cut from it so the plan is updatable in place), the feature PR's
diff is computed against the *docs branch*, not the default branch. Forward-syncing only the
feature branch then makes the feature PR's diff swallow everything the default branch gained —
hundreds of files a reviewer has already seen elsewhere — while the docs PR still goes
`CONFLICTING` on its own index line. Sync both, in order:

```bash
git checkout <docs-branch> && git merge --no-edit origin/<default>   # resolve the index; push
git checkout <feature-branch> && git merge --no-edit <docs-branch>   # brings the default branch in through the base; resolve; test; push
```

The docs-branch merge typically conflicts only on `docs/ideas/README.md` (keep both sides in
ship order); the feature-branch merge is where the real conflicts live (a shared test file both
IDEAs amended → keep-both in the class docblock; a generated artefact → take the incoming copy
and **regenerate**, never hand-merge). Both PRs then read `MERGEABLE` and the feature PR's diff
stays exactly its own commits. Merge order at the human's click stays docs → retarget feature
to the default branch → feature.

Two things a stacked wrap exposes that a single-branch wrap hides: (a) an index edit made at
`/plan` time on the docs branch is *also* what the feature PR ships, so a mistake there (a
placeholder substituted in every section instead of one) surfaces at wrap on both PRs — fix it
on the docs branch, where it belongs; (b) the review engine that skip-no-ops pushes after its
first review will not re-review either branch's sync merge — read the test workflow for the
merged tree, and retrigger explicitly if a docs pass-2 is wanted.

## An IDEA number is reserved at MERGE time, not at file-creation time

`/wrap` files the follow-up IDEAs the sprint surfaced, and it picks their numbers by scanning
for the highest one currently visible. On a repo with parallel IDEAs in flight, **that scan is
stale the moment it runs**: a sibling wrap on another branch may have already filed the same
NNN and simply not merged yet. Nothing catches it — the two IDEA files have different slugs, so
they are *different paths*, and git merges them without a whisper of conflict. Both land. The
index then carries two rows for the same number, in different priority sections, and the two
archives cross-reference "IDEA-NNN" meaning two different things.

Field case: two wraps a few days apart each filed a follow-up IDEA and both picked the same
number. The second one's forward-sync merged cleanly; the collision was visible only because the
resolver happened to read the index's backlog sections and noticed the number appear twice.

**So re-scan for collisions at every forward-sync, not just when the number is first chosen** —
and scan wider than the working tree:

```bash
git ls-tree -r --name-only origin/<default> -- docs | grep -oE 'IDEA-[0-9]{3}' | sort -u | tail -3
for b in $(git ls-remote --heads origin | awk '{print $2}'); do … same scan per branch … done
```

**Who renumbers:** whichever side has *not* merged yet. The number belongs to the branch that
reached the default branch first — renumbering a merged IDEA breaks links other archives and
devlog entries already point at. Renumbering is mechanical but has six surfaces, and missing any
one leaves a dangling reference:

1. the file name (`git mv`),
2. the frontmatter `id:`,
3. the body `# IDEA-NNN:` heading,
4. the ideas-index backlog row (link text *and* href),
5. the originating IDEA's archive `README.md` "Follow-up" line,
6. the devlog entry's follow-up line.

Then `grep -rn "IDEA-<old>"` across `docs/` and confirm every remaining hit belongs to the
*other* IDEA. Do it in the merge commit, and say so in the commit message — a reviewer seeing a
renumber with no explanation will assume it was a mistake.

## Checklist (Step 1 addendum)

- [ ] `git fetch origin && git log --oneline HEAD..origin/<default>` — non-empty?
- [ ] merge, resolve keep-both in ship order, lint/parse the resolved files, run the suite
- [ ] commit the merge **before** any wrap edit
- [ ] stacked pair? merge the default branch into the **docs** branch first, push, then merge the docs branch into the feature branch (regenerate artefacts instead of hand-merging them)
- [ ] incoming modules grepped for this IDEA's new convention; gaps recorded in index / devlog / CLAUDE.md
- [ ] IDEA numbers filed by this wrap re-scanned for collisions against the default branch **and every remote branch** — the loser (whoever hasn't merged) renumbers across all six surfaces
- [ ] after the final wrap push: `gh pr view --json mergeable` is `MERGEABLE`
