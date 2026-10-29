# A version number is a claim other open PRs can already hold

Load when Step 4b is about to bump a version source (`VERSION`, `package.json`, a versioned
`CHANGELOG.md`) in a repo where more than one feature PR is open at once.

## The failure

Step 4b detects the project's policy from history ("the last two releases each advanced the minor on
their own PR"), applies it to the *default branch's* version, and writes `current + 1`. That is
correct in isolation, and wrong whenever another open PR has already written the same `current + 1`
on its own branch. Neither branch conflicts with `main`. Both read MERGEABLE, and both CHANGELOGs are
internally consistent. The collision surfaces only when the second PR is updated after the first
merges. By then a runsheet, a paired release in a sibling repo, or a release note may already quote
the number.

Field case: a wrap bumped to `0.25.0` about thirty-five minutes after a concurrent PR had claimed
`0.25.0`, and that PR was paired with a sibling repo's release on an evening deploy runsheet. The
collision was caught by the human, not the wrap. The wrap PR was renumbered to `0.26.0` with "merge
after the other PR". The human then merged the wrap PR **first**, so the default branch went
`0.24.0 → 0.26.0` with the other PR still open, `CONFLICTING`, and holding a number now below the
default branch's.

## The rule

1. **Read every open PR's claim before choosing a number.** For each open PR against the release
   branch, read the version source on its head. For example:
   `gh pr list --state open --base <default> --json number,headRefName,title`, then
   `git show origin/<head>:VERSION`, or the topmost `## [x.y.z]` of its `CHANGELOG.md`. The PR title
   often carries the number too.
2. **A number another open PR holds is taken.** Choose the next free one, or ask. The PR that claimed
   first keeps it, especially when a sibling-repo pairing or a runsheet already names it. Renumbering
   the *other* PR is the user's call, never the wrap's.
3. **Write the dependency where the merger will see it:**
   - the PR description ("ships after #N, which owns x.y.z; merge #N first");
   - the CHANGELOG section's first line;
   - the conflict each PR will take (usually the version source and the CHANGELOG head only), and how
     to resolve it (keep both sections, newest on top).
4. **Plan for the human merging out of order.** It happens. The resolution belongs on the late PR's
   branch and is owned by that PR's author:
   - the version source never goes backwards: keep the higher number already on the default branch;
   - the late PR's CHANGELOG section slots in **below** the newer one, keeping its own number and
     date;
   - "x ships after y" sentences on the default branch become true again once it lands.

   At post-merge, detect this and say it in the hand-back:
   `git show origin/<default>:VERSION` against each still-open PR's claim. Do not push to another
   author's branch to fix it.

## A release ships every merge since the last one — read its changelog against that window

When the wrap cuts a version from the default branch, the release carries **every PR merged since
the previous version**, not only this IDEA. Projects that log IDEAs in the devlog and operational
PRs (deploy tooling, hotfixes) only in the changelog drift: an ops PR merged without its changelog
line now ships unnoted inside a release named after a feature. Before writing the version section:

```bash
gh pr list --state merged --base <default> --search "merged:><previous release date>" --json number,title
```

and match each number against the changelog (`[Unreleased]` + the new section). Missing ones
(≤ 3) are backfilled into the new section from their PR bodies — say which in the hand-back so the
owner reviews bullets they did not write; more than three → ask. If `[Unreleased]` holds entries,
whether the new version absorbs them is the owner's call (ask with the rest of Step 4b), and the
headline paragraph names everything the version carries, not only the IDEA. Field case: a feature
release absorbed two `[Unreleased]` entries and three ops PRs that had merged with no changelog line
at all.

## Checklist (Step 4b, before editing the version source)

- [ ] Open PRs against the release branch listed; each head's version claim read.
- [ ] Chosen number is free across `main` **and** every open head.
- [ ] If another PR holds the obvious number: user asked, answer recorded in the CHANGELOG line and
      the PR description.
- [ ] Post-merge: the default branch's version compared with every still-open claim; an
      out-of-order merge reported with the late PR's resolution recipe.
- [ ] PRs merged since the previous version matched against the changelog; gaps backfilled into the
      new section (or asked about), `[Unreleased]` absorption decided by the owner.

## Related

- `../SKILL.md` § Step 4b: the bump triggers and the "never decide the number autonomously" rule
  this extends to concurrent PRs.
- [`PRE_WRAP_FORWARD_SYNC.md`](PRE_WRAP_FORWARD_SYNC.md): the forward merge that shows what has
  *merged*. This reference covers what is merely *open*.
