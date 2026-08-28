# engine-claude — Claude Code Review adapter (action + `code-review` plugin)

Adapter specification for the Claude review engine. The orchestrator at [`SKILL.md`](../SKILL.md) drives this engine via the tool surface; the reference surface (this file) documents quirks the agent needs when triaging findings.

## ⚠️ READ THIS FIRST — the action + `code-review` plugin is NOT the managed Claude Code Review App

This engine drives `anthropics/claude-code-action@v1` running the **`code-review` plugin** via a self-hosted `.github/workflows/claude-code-review.yml` workflow (OAuth/subscription-billed). It is **NOT** Anthropic's managed *Claude Code Review* GitHub App.

| Surface | Managed App (we do NOT use) | Action + `code-review` plugin (what we drive) |
| --- | --- | --- |
| Named check-run | ✅ `Claude Code Review` check-run | ❌ none — only the GitHub **Actions job** status |
| Machine-readable verdict | ✅ severity JSON | ❌ findings are plain inline + summary comments |
| Clean signal | severity JSON empty | summary-comment body substring OR zero head-SHA inline comments |

✅ **DO** read review-state off the **Actions job** of the `claude-code-review` workflow run, and clean off comment structure.

❌ **DON'T** look for a `Claude Code Review` check-run or severity JSON — anything you read at `code.claude.com/docs` describing those describes the *managed App* and **does not apply here**. There is no named check-run to poll; polling for one returns nothing and the loop hangs to HUNG.

## § Identity

- Vendor: Anthropic — `anthropics/claude-code-action@v1` running the `code-review` plugin.
- Install path: **do NOT rely on `/install-github-app`'s default template — it ships `pull-requests: read` / `issues: read`, which silently blocks the action from POSTING findings** (a findings-bearing run posts nothing → `find_claude_comments.sh` reads a FALSE CLEAN via the zero-inline arm). Onboard by committing **our own write-perm templates** ([`../assets/claude-code-review.yml`](../assets/claude-code-review.yml) + [`../assets/claude.yml`](../assets/claude.yml)) to the **default branch**, porting `find_claude_comments.sh` + `claude_retrigger.sh` into `tools/`, and wiring `CLAUDE_CODE_OAUTH_TOKEN`. Full procedure + the anti-tampering bootstrap catch-22 (why the perms change can only take effect from the default branch): [`engine-claude-onboarding.md`](engine-claude-onboarding.md). The drop-the-two-workflows part of `/install-github-app` is fine as a starting point — but immediately replace the perms + add the guards.
- GitHub UI surface — **comment-anchored, no named check-run**:
  - Inline findings on `/pulls/<N>/comments`.
  - A top-level summary comment on `/issues/<N>/comments`.
  - The only RUNNING/DONE surface is the **GitHub Actions job** of the `claude-code-review` workflow run (`/actions/workflows/claude-code-review.yml/runs`).
- **Identity — CONFIRMED `claude[bot]`** for posted reviews (findings-bearing run, downstream non-draft PR, 2026-06-03). When the action actually POSTS a review — inline findings **and** a top-level **"Code review" summary comment** — the author login is **`claude[bot]`**.
  - ⚠️ **The PR #167 dogfood "confirmed `github-actions[bot]`" was WRONG** — it calibrated on a CLEAN run that posted *no claude content*, mistaking the workflow's PR-size-check / `github-actions[bot]` comment for claude's review. Never calibrate identity off a run that posted nothing. `find_claude_comments.sh`'s `CLAUDE_LOGINS` includes `claude[bot]` (plus `github-actions[bot]` / `claude-code-action[bot]` as harmless over-coverage), so detection was robust either way — but the doc was wrong.
  - **Inline review comments → login-only** (login ∈ `CLAUDE_LOGINS`). Review output by construction; the safe direction (over-count → keep polling, never a false clean).
  - **Summary issue comment → BOTH-AND** (login AND body signature). A findings-bearing run **does** post a "Code review" summary (e.g. "N issues found … No bugs detected" / "No bugs or security issues found"), so this arm is **live, not dead backup** — and the body signature stops a stray bot "no issues" comment faking a clean.

## § Tool invocations

- `./tools/find_claude_comments.sh <PR_NUMBER>` — probes engine reachability (below), then synthesizes the contract-shape stream: `CLAUDE_CHECKRUN=... STATUS=<queued|in_progress|completed>` from the **Actions job** (latest run by `run_started_at` for the head SHA), `CLAUDE_LATEST_REVIEW=...` anchored on the summary-comment id (or newest head-SHA inline comment id if no summary), inline finding blocks each carrying the mandatory `(comment id <cid>, review <rid>)` token, **summary-BODY finding blocks** carrying `(comment id <cid>, review summary)` when the `## Code review` summary itself is findings-bearing (the C1 surface — see § calibration update — findings live in the SUMMARY BODY), and an optional legacy `CLAUDE_CLEAN_SIGNAL=...` (non-authoritative). May also emit `CLAUDE_NOT_INSTALLED=true` (reachability), `CLAUDE_DRAFT_NOOP=true` (draft PR — no review), or `CLAUDE_REVIEW_PENDING=...` (race guard).
- `./tools/claude_retrigger.sh <PR_NUMBER>` — **fallback only.** Posts the hard-coded `@claude review once` comment. Pre-approvable in `~/.claude/settings.json`. See § Push-triggered model below — Phase 3 does NOT call this after a fix push.

**Reachability probe (A2 / R4).** `find_claude_comments.sh` probes `gh api .../actions/workflows` for `claude-code-review.yml` by filename. If the workflow is absent it emits `CLAUDE_NOT_INSTALLED=true` and exits 0, so the orchestrator's default-engine resolution can **self-exclude** claude rather than poll an un-provisioned engine to HUNG.

✅ **DO** let claude self-exclude from the *default* set on repos where the action isn't installed.

❌ **DON'T** treat `CLAUDE_NOT_INSTALLED=true` on an *explicit* `/review-loop <PR> claude` as a silent skip — it degrades **loudly**: hand back with a clear "claude action not installed (run `/install-github-app`)" message. Loud-not-silent is the contract.

## § Pre-flight: default-branch perms gate (2026-08-18, downstream field observation)

**Before triggering anything** (bootstrap trigger, `gh pr ready` un-draft, or a fix push), read the **default branch's** copy of the workflow — that copy, not any branch's, is what `pull_request` events execute:

```bash
git show origin/<default>:.github/workflows/claude-code-review.yml | grep -A4 'permissions:'
```

If it says `pull-requests: read`, **every run is structurally muzzled** — it will complete job-`success` and post nothing, no matter how many times the loop triggers. Hand back **immediately** with the onboarding instruction instead of entering the trigger→poll→SILENT→diagnose cycle (field-observed: two billed silent runs before the perms were checked — both avoidable at pre-flight, since the loop already knew the failure signature). The existing § Failure modes SILENT handling remains the *post-hoc* diagnosis path for runs already spent; this gate is the *pre-hoc* short-circuit that makes those runs unnecessary. Note the § Incremental review consequence compounds the cost: the muzzled first pass is the PR's only *full* pass, so every avoided muzzled run preserves recoverability.

**Feature-branch copy may lag the default branch (2026-08-22, downstream field observation).** The gate above reads the *default* branch's workflow because that is what `pull_request` events execute against — but the **feature branch's own copy** is what the action validates byte-for-byte (anti-tampering), and a branch cut *before* the perms fix merged still carries the old read-only file. Field case: the hardened workflow landed on the default branch (as its own PR) while a feature branch was mid-`/work`; at `/review-loop` time the branch's copy said `pull-requests: read` while `origin/<default>` said `write`. Resolution is a one-liner and is always-allowed forward-sync per `RULE_git-safety`: `git merge origin/<default>` into the feature branch (only the workflow files change), re-run the suite, push, **then** `gh pr ready`. Make the diff check part of the pre-flight — `git diff HEAD origin/<default> -- .github/workflows/claude-code-review.yml .github/workflows/claude.yml` non-empty ⇒ merge before un-drafting. Doing it in this order means the un-draft fires the PR's one full-diff review (§ Incremental review) against a branch whose workflow matches the default branch, instead of spending that unrecoverable first pass on a validation failure or a muzzled run.

**Orphaned-onboarding-branch trap.** When the gate fires, also check whether a hardened-workflow branch already exists (`git branch -a | grep -i claud`, or the project's onboarding-branch convention) before authoring a fresh fix: a prior session may have prepared the fix in a scratchpad worktree that has since evaporated — branch intact, **PR never opened**, onboarding silently incomplete. Two hand-off caveats: (1) permission classifiers may block an agent's `gh pr create` on PRs touching `.github/workflows/` — if blocked, push the branch and hand the compare-URL to the human explicitly rather than retrying; (2) the fix only takes effect once merged to the **default branch** (the onboarding catch-22), so the hand-back must say "merge to `<default>` first, then re-run the loop", not just "open the PR".

The `claude-code-review.yml` action auto-runs on every push (`synchronize`), **but the `code-review` plugin skips the auto-run once claude has already posted a review on the PR** — it posts a `## Code review\n\nSkipping review — Claude has already posted a code review comment` no-op instead of a fresh review. So the push is the retrigger **only for the first review**:

- The **push auto-run produces a real review ONLY the first time** claude sees the ready PR (any push before claude has commented). 
- Every **subsequent push auto-SKIPS** → no fresh verdict (a "Skipping review …" no-op, caught by `CLAUDE_NOOP_PATTERNS`). Verified PR #169: pushes `06b3a3b` + `16e6dd4` both skip-no-op'd after the first review on `7399749`.
- An **explicit `@claude review`** (`claude_retrigger.sh`) **overrides the skip and forces a fresh review.** Verified PR #169: the explicit retrigger produced a full 3-minute review where the two prior pushes had skipped. Note the explicit path posts in the **@-mention / task format** ("Claude finished @user's task … ### Code Review …") — a different shape than the auto "## Code review" summary; the catch-everything classifier (§ Review-state + clean detection) handles both.

✅ **DO** let the **FIRST** claude review come from the push / un-draft auto-run (no explicit retrigger needed before claude has commented).

✅ **DO** fire `claude_retrigger.sh` after a Phase-3 fix push **once claude has already reviewed the PR** — the push auto-run will skip, so the explicit `@claude review` is the only thing that gets a fresh verdict on the fix. **This REVERSES the prior "the push IS the retrigger, don't double-fire" guidance, which was wrong for the 2nd+ review** (the feared double-run race doesn't occur: the auto-run skips, so the explicit retrigger is the sole review).

❌ **DON'T** expect a fix push alone to re-review after claude's first comment — it skip-no-ops, and the loop will read the stale prior verdict (or a no-op) until you explicitly retrigger.

The retrigger script also covers the **zero-activity bootstrap**: no Actions run at all for the head SHA (fresh PR / just-installed workflow).

**⚠️ The explicit `@claude review` runs a DIFFERENT workflow than `find` tracks — so `CHECKRUN` goes STALE post-retrigger (confirmed 2026-06-23).** The push/synchronize auto-run is the **`Claude Code Review`** workflow (`claude-code-review.yml`, `pull_request` event) — the only one `find_claude_comments.sh` reads its Actions-job status from. But `claude_retrigger.sh`'s `@claude review` comment triggers the **separate `Claude Code`** workflow (`claude.yml`, `issue_comment` event), which `find` does **not** track. So after an explicit retrigger:

- `CLAUDE_CHECKRUN` / `STATUS` is read from the *stale* `claude-code-review.yml` run — typically the just-pushed synchronize **skip-no-op** (it completes near-instantly), NOT the live `@claude` review run. It reports `STATUS=completed` while the real review is still running.
- The verdict **comment**, meanwhile, is posted by the untracked `@claude` run. While that run is in-progress the comment is the **unchecked progress-checklist placeholder** (`- [ ] Read … - [ ] Synthesize findings`), which the summary-body classifier can match as `FINDINGS=true`.
- Net: `find` emits a `completed` CHECKRUN **mixed** with an in-progress run's placeholder comment → a **false / premature verdict** (false `FINDINGS=true`, or a false CLEAN if the placeholder reads empty). Observed twice in a single loop.

✅ **Mitigation — after ANY explicit retrigger, verify against the `@claude` run directly, not `find`'s CHECKRUN.** Don't trust `STATUS=completed` post-retrigger. Instead: (1) find the `Claude Code` (`claude.yml` / `issue_comment`) run for the head SHA and confirm **it** is `completed`; (2) re-read the summary-comment **body** and confirm the checklist is **finalized** (zero `- [ ]` boxes — all `- [x]` + an Issues/clean section), not the in-progress placeholder; (3) decide clean **structurally** — zero active *inline* findings on the head SHA — never off the prose-matched `FINDINGS=true` flag (the summary routinely discusses *prior-cycle resolved* issues by name, tripping the flag while the verdict is actually clean).

**Dedup.** `find_claude_comments.sh` always selects the **latest Actions run by `run_started_at`** + the newest summary comment for the head SHA, so any auto-run / fallback overlap collapses to one authoritative signal — **but only within `claude-code-review.yml`**; the `@claude`-mention `claude.yml` run is invisible to this dedup (see the ⚠️ above), which is why the post-retrigger CHECKRUN can be stale.

### ⚠️ DRAFT PRs get NO posted review — the action runs but posts nothing

**On a draft PR, the Actions run fires (`synchronize` fires on draft pushes) and concludes `success`, but claude POSTS NOTHING** — no inline findings, no summary. So a draft PR reads as **SILENT / false-clean-vector**, *not* clean. Confirmed by an A/B on one commit (downstream, 2026-06-03): the same tree read SILENT while draft and posted a full review (summary + 2 inline findings) the instant the PR was marked **ready for review**. This — not `#1087` — was the actual cause of every "ran but posted nothing" result during the engine's bring-up; the `#1087` post-session-capture bug is a *separate*, rarer failure.

✅ **DO** ensure the PR is **ready-for-review (not draft)** before trusting a claude verdict; the workflow already lists `ready_for_review` in its trigger types, so un-drafting auto-fires a real review.

❌ **DON'T** read a draft PR's silence as a finding about the code — it's the draft no-op.

**Adapter belt-and-suspenders:** `find_claude_comments.sh` now probes `gh ... pulls/<PR> .draft` up-front and, on a draft PR, emits **`CLAUDE_DRAFT_NOOP=true`** + exits early (instead of fetching runs → eventually SILENT). So even if `/review-loop`'s pre-flight un-draft is skipped or fails, the loop sees a clear "no claude verdict until ready (un-draft the PR)" signal, never a misattributed SILENT/HUNG/clean. In normal flow the pre-flight un-drafts before Phase 1, so this never fires.

**✅ Use the draft no-op as a deliberate lever — the recommended sprint cadence.** claude is the only **push-triggered** engine (bugbot/copilot are on-demand inside the review-loop), so a non-draft PR auto-runs — and bills — a claude review on **every** `/work` commit push. Keep the PR in **draft during `/work`** to suppress that, iterate freely, and **flip to ready-for-review after `/wrap`** — that single un-draft fires one intentional claude review on the finalized state, which the `/review-loop` then drives alongside bugbot/copilot. Net: one billed review per cohesive change instead of one per WIP push, and no SILENT-on-WIP noise. (If you *want* a mid-`/work` claude pass, momentarily mark ready or trigger bugbot/copilot, which don't need the un-draft.)

## § Review-state + clean detection

**Review-state is synthesized from the Actions job, not a check-run.** `find_claude_comments.sh` filters `claude-code-review.yml` runs to the head SHA, picks the latest by `run_started_at`, and maps `queued`/`in_progress` → **RUNNING**, `completed` → **DONE**. The Actions `CONCLUSION` is **green whether claude found 0 or 5 issues** — it is a RUNNING/DONE signal only, NEVER a verdict.

**Clean requires a POSITIVE posted signal — never zero-inline alone (A6 / LAYER 2).**

```text
clean    ⟺  claude POSTED a clean summary (body contains case-insensitive
            substring "no issues found")  AND  zero inline findings
findings ⟺  inline comments posted on the head SHA
SILENT   ⟸  run `success` (DONE) but NOTHING posted after settle
            → NOT clean (held RUNNING; see § Failure modes)
```

**Why not "zero inline = clean" (the original A6 belt-and-suspenders, reversed by verified research).** A claude run can report `success` having posted **nothing** — action issue [#1087](https://github.com/anthropics/claude-code-action/issues/1087): the plugin buffers inline comments for a post-session step whose result-capture grabs a `TodoWrite` response instead of the review → empty → no comment. "success + silent" is **indistinguishable from genuinely-clean** ([#1054](https://github.com/anthropics/claude-code-action/issues/1054)) by run status, so zero-inline is a **false-CLEAN vector**, not a clean signal. Clean now demands a posted clean summary; the **fixed workflow** ([`../assets/claude-code-review.yml`](../assets/claude-code-review.yml) — `classify_inline_comments:false` + `claude_args` post-during-run + a prompt that forces a posted summary *even when clean*) is what makes a genuinely-clean run actually post that summary. The substring (not the full sentence) follows the copilot lesson (`find_copilot_comments.sh:182-189`).

The legacy `CLAUDE_CLEAN_SIGNAL` line is corroboration only; the orchestrator derives clean structurally (DONE + zero active findings) — which is correct ONLY because the adapter holds a no-verdict run RUNNING (so DONE is reached only with a posted clean summary or posted findings).

✅ **DO** read clean off a POSTED clean summary + zero inline findings.

❌ **DON'T** read clean off zero-inline alone, nor off the Actions `CONCLUSION`. Both pass on a #1087 silent drop → false CLEAN.

## § Staleness rule

Keyed on **comment ids** (synthesized anchor), not a review id. `CLAUDE_LATEST_REVIEW` = the summary-comment id, or the newest head-SHA inline comment id when no summary exists. Each inline finding carries `(comment id <cid>, review <rid>)`; whether the inline comments share a single `pull_request_review_id` is **unconfirmed** (Q1, § residual open questions) — the anchor keys on the comment id either way, so the rule is safe regardless. When `<rid>` is null/absent the orchestrator tolerates an empty review token for comment-anchored engines.

**Time-axis guard (load-bearing — see § Stale summary on a new SHA below):** a summary comment is only a verdict for the head SHA if its `created_at` is **later than the head commit's push**. `find_claude_comments.sh` stamps `CLAUDE_LATEST_REVIEW` / `CLAUDE_SUMMARY_ID` with the *current* head `COMMIT=` even when the summary predates it, so the orchestrator must compare `AT=` against `git log -1 --format=%cI HEAD` (or the PR's `pushedAt`) before reading CLEAN.

## § Stale summary on a new SHA — the skip-no-op false CLEAN

Field-observed (2026-08-22). Sequence: first review posts a clean summary on SHA₁ → a fix is pushed (SHA₂) → the `synchronize` auto-run fires, **completes `success` in ~70 s and posts nothing** (the plugin skips because claude already reviewed the PR — § Push-triggered model) → `find_claude_comments.sh` now emits:

```text
CLAUDE_CHECKRUN=<run> COMMIT=<SHA₂> STATUS=completed CONCLUSION=success
CLAUDE_LATEST_REVIEW=<summary-id-from-SHA₁> COMMIT=<SHA₂> AT=<SHA₁ time> CLEAN=true
CLAUDE_SUMMARY_ID=<summary-id-from-SHA₁> ... CLEAN=true FINDINGS=false
```

Every structural signal reads CLEAN for SHA₂ — DONE check-run, positive clean summary, zero inline — yet **no review of SHA₂ ever happened**. The only tell is `AT=` (13:12) being *earlier* than the SHA₂ push (13:33). An orchestrator that trusts the stream hands back CLEAN on unreviewed code.

✅ **DO**, on every wake where `last_push_sha` changed: (1) compare the summary's `AT=` to the head commit time — older ⇒ **no verdict for this SHA**, treat as `NOT_TRIGGERED`; (2) confirm by listing `claude[bot]` issue comments newer than the push (none ⇒ skip-no-op); (3) fire `claude_retrigger.sh` **once** and then verify against the `claude.yml` (`issue_comment`) run + the new task-format comment, per § Push-triggered model's mitigation.

❌ **DON'T** read `CLEAN=true` on a freshly-pushed SHA without the time check — the finder's `COMMIT=` on the `LATEST_REVIEW` line is the *head* SHA, not the SHA the summary reviewed.

**Adapter guard (done 2026-08-25, second field occurrence).** `find_claude_comments.sh` now fetches the head commit's committer date and, when the selected summary's `created_at` is older, emits `CLAUDE_STALE_SUMMARY=true SUMMARY=<id> SUMMARY_AT=<ts> HEAD_COMMIT_AT=<ts>` and drops the summary's clean/findings signals before the verdict gate — so the run falls through to `CLAUDE_REVIEW_PENDING` / `CLAUDE_REVIEW_SILENT` (never CLEAN) and `CLAUDE_LATEST_REVIEW … CLEAN=false`. The orchestrator no longer needs the manual date compare; on `CLAUDE_STALE_SUMMARY=true` treat the engine as `NOT_TRIGGERED` for the head SHA and fire `claude_retrigger.sh` once (the DO-list above). Head-SHA inline findings are unaffected by the guard — they are filtered by SHA already.

**Pre-check before the retrigger (2026-08-25, sibling of the stale-summary case).** `CLAUDE_STALE_SUMMARY=true` + no check-run for the head SHA has a second cause where `claude_retrigger.sh` is the *wrong* move: the PR is `CONFLICTING` (base moved under the branch), so GitHub created **no** `pull_request` run for the push — nor for a `reopened` — and the project's test workflow is equally silent. Run `gh pr view <N> --json mergeable` first; on `CONFLICTING` forward-sync and push instead of retriggering. See [`CONFLICTING_PR_NO_CI.md`](CONFLICTING_PR_NO_CI.md).

## § Race-condition caveats

**The settle valve releases on comment PRESENCE, not Actions conclusion (A3 — load-bearing).** This is the divergence from copilot's `CONCLUSION=success` settle gate. claude's Actions job flips to `completed` *before* its summary/inline comments post — a poll in that gap sees DONE + zero findings → false CLEAN.

So a `completed` Actions run with **no readable verdict** (no posted findings AND no clean summary) is held at `STATUS=in_progress` (RUNNING) so the orchestrator's "DONE + zero findings = CLEAN" can't fire on it. The settle window (`CLAUDE_REVIEW_SETTLE_SECONDS`, default **180**) only picks the marker — it never releases a no-verdict run to DONE:

- **within window** → `CLAUDE_REVIEW_PENDING` (comments may still be landing — race).
- **window elapsed** → `CLAUDE_REVIEW_SILENT` (nothing came → **NOT clean**: #1087 drop / read-only perms / un-fixed workflow). Stays RUNNING; the loop hands it back as uncertain (re-trigger / verify perms), never auto-clean.

**Settle window is 180s, not copilot's 600 (calibrated PR #167).** claude-code-action posts its inline comments *synchronously within the job* — the post step runs **before** the run reports `completed`, so comments (if any) already exist at completed-time. The window only covers GitHub API read-consistency after that in-job post, not copilot's minutes-long async-review lag.

✅ **DO** treat `CLAUDE_REVIEW_SILENT` as uncertain/needs-retrigger — never clean.

❌ **DON'T** copy copilot's `CONCLUSION=success` settle gate, and DON'T release a no-verdict run to DONE on settle-elapse (the original "zero-inline arm" — that's the #1087 false-CLEAN). claude concludes `success` even WITH findings, so conclusion is never consulted.

Settle age is computed in Python `datetime` (cross-platform), never `date -d`.

## § Failure modes

| Symptom | Detection | Orchestrator action |
|---|---|---|
| claude action not installed | `CLAUDE_NOT_INSTALLED=true` (no `claude-code-review.yml` workflow on the repo) | Self-exclude from the **default** set (bare `/review-loop`); on an **explicit** `claude` run, degrade **loudly** — hand back with "run `/install-github-app`", never HUNG, never silent. |
| **Draft PR (no review posted)** | `CLAUDE_DRAFT_NOOP=true` — the PR `.draft` is `true` (adapter early-exits) | Not a verdict — the draft no-op. `/review-loop` pre-flight should have un-drafted (`gh pr ready`); if this still fires, un-draft and re-poll. NEVER read as clean/SILENT/HUNG. |
| claude stalled | Actions job `STATUS=in_progress` (RUNNING) past observed latency on `last_push_sha` | Proceed with other engines' findings if any; do NOT explicitly retrigger (push-triggered — the next fix push re-runs it). Surface in hand-back if it doesn't recover within the idle-poll budget. |
| Actions job unreadable | `actions: read` blocked for the user's `gh` auth — `WORKFLOW_RUNS` empty, no `CLAUDE_CHECKRUN` (Q3) | Degrade to summary-comment-only state (lose the RUNNING signal) with a logged warning. Do NOT hard-fail the loop. |
| **Silent run (success + nothing posted)** | `CLAUDE_REVIEW_SILENT=...` — run `completed`/`success` but NO findings and NO clean summary after settle (held RUNNING) | **NOT clean.** (When the cause is a read-only default-branch workflow, § Pre-flight perms gate should have short-circuited before any run was spent.) Hand back as uncertain: re-trigger once, and verify the workflow has the reliability fixes + `pull-requests: write` (LAYER 1/2). Most likely the #1087 buffer-drop, a read-only-perms posting block, or an un-fixed/old workflow — never read as a clean pass. Don't wait for the full idle-timeout; the SILENT marker is the terminal signal. **Retrigger-futility check first (2026-08-18):** the explicit retrigger runs the `claude.yml` mention workflow, NOT `claude-code-review.yml` — read `claude.yml`'s `permissions:` before firing; if it is read-only (`pull-requests: read`), the retrigger is a billed muzzled no-op — skip it and say so loudly. When the retrigger is futile (or the muzzled first pass is spent per § Incremental review), substitute an **independent reviewer subagent over the PR's net diff** (the [`LARGE_PR_INDEPENDENT_REVIEW.md`](LARGE_PR_INDEPENDENT_REVIEW.md) shape, or the project's local reviewer persona) so the loop still hands back a real verdict — and ship the canonical-workflow fix as its own PR to the default branch in the same session (it only takes effect from there). |

**Robust-mode alternative (record-only).** #1087 is an *open* upstream bug — the workflow fixes *mitigate* (post-during-run) but don't *guarantee* (the model can still end on a `TodoWrite` before posting). For guaranteed reliability, Anthropic's **managed Code Review GitHub App** (`@claude review`, Team/Enterprise) writes findings to **check-run annotations** independent of the comment buffer — but it's paid (~$15–25/review), research-preview, and unavailable under Zero Data Retention. If a project hits persistent SILENT despite the fixes, the managed App is the escalation path (a different adapter — it *does* post a named check-run, unlike this action path). Tracked in IDEA-012.
| Review-pending race | Actions job `completed` but no head-SHA summary/inline comment yet | Downgraded to RUNNING + `CLAUDE_REVIEW_PENDING` (§ Race-condition caveats). Keep waiting; never a premature CLEAN. |

## § Incremental review + the `num_turns` diagnostic — a re-trigger on an already-reviewed diff SILENTs by DESIGN

The SILENT handling above assumes a silent run means *something went wrong* (buffer drop / read-only / un-fixed workflow) and prescribes "re-trigger once + verify perms." There is a **second, benign** cause of a silent run that re-triggering does **not** fix: the `code-review` plugin reviews the **incremental diff since its own last review of the PR**, not the whole PR each trigger. So a trigger that presents *nothing new to review* completes `success`, posts nothing, and reads SILENT — correctly, because there was nothing to say.

This bites in two shapes:

- **Re-trigger on an unchanged head SHA** (a `close`+`reopen` to force a re-review, or any trigger without a new commit) → the plugin has already reviewed this SHA → **deduped no-op**.
- **A tiny follow-up push** (a one-line fix) → it reviews only that one-line increment → a near-no-op — which is *not* a verdict on the rest of the PR.

**Consequence — the FIRST full pass is the only full pass, and it can't be recovered on the same PR.** If that first full review was muzzled (read-only perms) or dropped (#1087), fixing the workflow afterwards does **not** get you a fresh full review of that PR: every subsequent trigger only sees increments. Re-triggering in a loop just re-SILENTs. To force a fresh full-diff review you must make the plugin treat the PR as new — a **`opened` event**, i.e. **open a fresh PR** from the same branch (a `reopen` is not enough; it dedupes). Absent that, fall back to an **independent reviewer** (a subagent over the net diff — see [`LARGE_PR_INDEPENDENT_REVIEW.md`](LARGE_PR_INDEPENDENT_REVIEW.md)) rather than trusting a deduped no-op.

**The `num_turns` diagnostic distinguishes the two silent causes.** The claude-execution result JSON in the run log carries `num_turns` and `permission_denials_count`. Read them before classifying a silent run:

- **`num_turns` in the tens** (a substantial diff genuinely takes ~30–60 turns) + `permission_denials_count: 0` + nothing posted → a real clean pass *or* a buffer drop (#1087) — the existing SILENT handling applies (verify perms are `write`; if so, suspect #1087).
- **`num_turns` single-digit** (4–9) → **check `permission_denials_count` BEFORE reading this as a no-op** — the denials check outranks the turn-count heuristic. A muzzle truncates the session early, so a muzzled run can ALSO land in single digits (field-observed 2026-08-18: 9 turns, 12 denials, ~$1.9 real cost, nothing posted — a muzzled run, NOT a dedupe; the earlier 34-turn signature was just one shape of muzzling). Only with `permission_denials_count: 0` does single-digit + ~real-cost mean the plugin did almost no work → **incremental/deduped no-op**, not a verdict on the PR. Re-triggering will not help; open a fresh PR or use an independent reviewer.
- **`permission_denials_count` > 0** on a run that otherwise did real work → the posting tools were **denied** → false-CLEAN vector. TWO distinct causes — check perms first, then tooling:
  - **Perms are read-only** (`pull-requests`/`issues: read`) → the token can't post at all. Fix perms (§ Identity).
  - **Perms are already `write` but denials STILL fire** → the workflow is missing the posting-tool **allowlist**: `claude_args: --allowedTools "Bash(gh:*),mcp__github_inline_comment__create_inline_comment"`. Write perms are **necessary but not sufficient** — the action's default tool policy blocks `gh pr comment` + the inline-comment MCP tool unless they're explicitly allowed. The bare `/install-github-app` template (and any partial retrofit that raised perms but didn't add the tooling) hits this. Fix by shipping the FULL canonical [`../assets/claude-code-review.yml`](../assets/claude-code-review.yml) (allowlist + `classify_inline_comments:false` + post-during-run prompt), **not** another perms edit. Field signature: `permission_denials_count: 17` on a `write`-perm run that reviewed the full diff (34 turns, real cost) but posted nothing.
  In both cases the muzzled pass is *spent* per the paragraph above.
- **`is_error: true` + `num_turns: 1` + `total_cost_usd: 0` + `permission_denials_count: 0` + duration ~2s** → the model turn failed at the **first API call**, before any billable work → the **`CLAUDE_CODE_OAUTH_TOKEN` is invalid/expired** (or the subscription/credits behind it are dead). This is a FOURTH silent cause, distinct from the three above: it is NOT #1087 (no turns ran), NOT muzzled (denials are 0), NOT a deduped no-op (that does real work at ~$0 but `is_error:false`). The init line still says `Claude Code initialized` and the GitHub Actions job still reports **`success`** — the action swallows the error — so the ONLY tell is the result JSON (`is_error`/`num_turns`/`total_cost_usd`) in the run log. Re-triggering reproduces it identically at $0; it will never resolve without a new token. **Fix:** rotate the token — `claude setup-token` (interactive browser OAuth) then set the repo secret. ⚠️ **`gh secret set` needs a real TTY:** run in a genuine terminal, not a non-interactive `!`/piped shell — a TTY-less `gh secret set CLAUDE_CODE_OAUTH_TOKEN` reads empty stdin and stores an **empty** value, which then fails a *later* run with `Environment variable validation failed: Either ANTHROPIC_API_KEY, CLAUDE_CODE_OAUTH_TOKEN … is required` (a different, louder error than the swallowed $0 one — empty is caught by validation, invalid is not).

So: `num_turns` (full vs single-digit vs 1), `total_cost_usd` ($0-with-`is_error` vs $0-clean-work vs real cost), and `permission_denials_count` (muzzled vs not), read from the run log, separate **four** states that all present identically as job-`success` + zero posted comments — "genuinely nothing to flag," "muzzled," "deduped no-op," and **"dead token."** Never calibrate a claude verdict from the check-run status + comment count alone when any of these is in play.

**Transient companion — spurious "workflow validation failed" after two `App token exchange failed: 500`.** Right after fixing perms/token, a re-run may fail the *step* (not just swallow) with `Workflow validation failed. The workflow file must … have identical content to the version on the default branch` — but only *after* two `App token exchange failed: 500 Internal Server Error` attempts. When the workflow file genuinely **does** match the default branch (verify: `git diff origin/<default> <branch> -- .github/workflows/claude-code-review.yml` is empty, and the PR's changed-file list shows no `.github/` paths), the validation error is a **symptom of the transient GitHub-App 500s**, not a real content mismatch — it clears on a clean re-run. Don't chase it as a workflow problem when the 500s precede it and the content matches.

## § Common patterns (codified Tier 1)

The codified Tier-1 catalogue is shared across engines — see [`common-review-findings.md`](common-review-findings.md). No claude-specific deltas at present; claude's behavioural quirks live in § Review-state + clean detection and § Race-condition caveats above. (claude's comment-body finding markers are now calibrated — see § calibration update — findings live in the SUMMARY BODY; the severity stamp on a summary-body finding is a heuristic, re-triaged by the loop.)

## § Review-state gate

claude exposes its review-state as `CLAUDE_CHECKRUN ... STATUS=<status>` **synthesized from the Actions job** (there is no native check-run — see the trap banner at the top). `queued`/`in_progress` = **RUNNING**, `completed` = **DONE**; `CONCLUSION` is never a verdict.

**Clean for claude**: Actions job DONE AND (summary-comment body contains "no issues found" OR zero active head-SHA inline findings matching `CLAUDE_LATEST_REVIEW`). The review-pending guard (§ Race-condition caveats) holds the loop in RUNNING until a head-SHA comment posts, so the DONE-before-comments gap cannot fire a false CLEAN. The orchestrator retriggers only from the zero-activity bootstrap (push-triggered otherwise) and never while RUNNING, so no inter-retrigger interval exists.

## § calibration update — findings-bearing + clean runs (downstream non-draft, 2026-06-03)

Two runs on the SAME commit, non-draft, settled the open questions:

- **Findings-bearing run → POSTS a full review.** ~9-minute run; posted inline findings + a top-level **"Code review" summary** ("N issues found … No bugs detected") under **`claude[bot]`**. So claude **does** post findings reliably on a ready-for-review PR — the long-pending findings-path question is answered YES.
- **Clean run → SILENT (still).** After the findings were fixed, the re-review on the clean tree finished in **~1 minute** and posted **nothing** — no inline, no summary — well past settle → `CLAUDE_REVIEW_SILENT`. **The LAYER-2 forced-summary prompt does NOT fire on a clean run**: the action short-circuits ("nothing to flag") and exits without posting the "no issues found" summary it was instructed to post. So the mitigation works for *findings* but not for *clean*. **(Scope-bounded 2026-08-18: this silent clean was a clean *re-review* — an incremental pass with ~nothing new to review. A clean FIRST full-diff run DOES post the forced summary — see § calibration update 2026-08-18 below.)**

**Net engine capability (action + `code-review` plugin):** posts **findings** reliably; a **positive clean verdict** posts on a clean **first full-diff review** (confirmed 2026-08-18, § below) and — scope-bounded again on 2026-08-26, § below — on a clean **explicit `@claude review` re-review after a fix cycle** (task-format comment, "gap fixed … No other issues found"). What still reads SILENT is the clean *push-triggered* (`synchronize`) re-run, which the plugin skip-no-ops after its first review. Consequence for the loop: claude contributes findings, green-lights a PR that is clean on first pass, **and** confirms clean after a fix cycle *provided the loop fires the explicit retrigger and reads the `claude.yml` run* (§ Push-triggered model mitigation). The managed Claude Code Review App remains the robust-mode answer only for the case where the explicit retrigger itself SILENTs — IDEA-012 narrows to that.

## § calibration update — findings live in the SUMMARY BODY (downstream, 2026-06-03)

The first *high-volume* findings-bearing run (13 `claude[bot]` summary comments across a long iteration) exposed that the prior "findings = inline comments + a short summary" model **undercounts where claude puts findings**. CALIBRATED against the real bodies; the adapter (`find_claude_comments.sh`) was fixed to match (the **C1** fix). Corrections (the last two added by the PR #169 self-dogfood — running this engine on the PR that ships C1):

- **Findings often post ONLY in the summary BODY, not inline.** claude's convention findings (CLAUDE.md docstring violations) and cross-file findings it can't line-anchor (privilege-escalation spanning a form + a view) are written as a structured report **inside the `claude[bot]` "## Code review" issue-comment body** — `### Bugs / Security`, `#### 1. …`, `### CLAUDE.md compliance / Docstrings missing …` — with **zero inline comments**. The old adapter only read the summary body for the clean substring, never surfaced its findings → claude's convention review was **invisible to the loop** (the user surfaced ~6 URL + ~30 docstring findings by hand). Fix: the adapter now surfaces a findings-bearing summary body as a finding block carrying `(comment id <cid>, review summary)`.
- **The summary heading is literally `## Code review` (space), which the old `code-review` (hyphen) signature did NOT match** → the whole summary was unrecognized. Signature widened to `code[ -]?review`.
- **Clean is WHOLE-REVIEW, not substring-anywhere.** claude clears sections independently: a single review says **"Bugs: No issues found."** in one section AND lists **"Docstrings missing"** in another. A bare `'no issues found' in body` test **false-cleans** that mixed review (the dangerous direction). Clean requires a positive clean phrase (`no issues/bugs/problems found`) AND the **absence of any finding marker** (structural, not security-keyword: a genuinely-clean review NAMES the concepts it checked, e.g. *"the privilege-escalation guard looks correct"*, so `privilege`/`escalation` as markers false-positive on clean prose). Re-validated against all 13 downstream bodies (2026-06-03): **3 NOOP, 9 FINDINGS** (incl. every mixed clean-bugs-but-dirty-compliance review), **1 CLEAN** (the final whole-review verdict) — **zero false-cleans** (the PR body's "2 NOOP / 10" was an off-by-one miscount; all three `Skipped` bodies are genuine no-ops).
- **No-op skip bodies must be filtered — ANCHORED.** claude posts `## Code review\n\nSkipped — …draft status` and `## Code review\n\nSkipped: …already reviewed this PR` issue comments that match the signature but are **not verdicts**. Anchored to the heading-then-`Skipped` shape (`^##\s+code[ -]?review\s*\n+\s*skipped`, `re.MULTILINE`) — **not** a bare search-anywhere — so a real findings body whose *prose* merely says "already reviewed in PR #N but regressed" is not false-filtered (PR #169 self-dogfood caught the old unanchored `already (posted|reviewed)` arm dropping exactly that — claude's finding body literally contained "already reviewed").
- **Surface is CATCH-EVERYTHING, marker-INDEPENDENT (PR #169 self-dogfood).** Review format is **non-deterministic** — count-line ("One issue found.") + ``### `file` `` headers in one run, `#### 1.` numbered + `### Bugs` sections in another, future runs may differ again. So the adapter does **not** require a matched marker to surface findings: a posted, non-no-op summary is **either provably-clean OR surfaced-as-findings** (`findings = posted ∧ ¬clean`). Markers now only gate the *clean* determination + severity. An unseen future finding shape therefore can never read SILENT. (The dogfood: claude posted "One issue found." under ``### `file` `` while reviewing this adapter; the marker-only logic read SILENT and dropped it — the inversion + anchored no-op are the fix.)

This does **not** change the net capability above: claude still posts findings reliably; the clean-verdict capability is per § calibration 2026-08-18 (first full-diff clean posts a summary; incremental clean re-reviews still read SILENT). The C1 fix only stops claude's *findings* — when they exist and live in the body — from being silently dropped.

## § calibration update — a clean FIRST full-diff run DOES post the forced clean summary (downstream, 2026-08-18)

First field observation of a **posted positive clean verdict** from this engine. On a downstream repo running the full canonical workflow (the [`../assets/claude-code-review.yml`](../assets/claude-code-review.yml) shape: posting-tool allowlist + `classify_inline_comments:false` + post-during-run forced-summary prompt), the **first review of a small ready-for-review PR** — auto-fired by the un-draft (`ready_for_review`), full-diff, ~10-minute run — completed with a `claude[bot]` summary:

```text
## Code review

No issues found. Checked for bugs and CLAUDE.md compliance.
```

plus **zero inline findings**. `find_claude_comments.sh` classified it whole-review clean (positive phrase, no finding markers) and the orchestrator reached a structural CLEAN with zero fix cycles.

What this changes, precisely:

- **The forced-summary prompt DOES fire on a clean run — when the run is a first full-diff pass.** The 2026-06-03 "clean run → SILENT" observation is not contradicted but **scope-bounded**: that run was a clean *re-review after a fix cycle*, i.e. an incremental pass with ~nothing new to review (§ Incremental review) — the short-circuit path exits before the summary posts. A first pass over a real diff that finds nothing goes through the full review path and posts the instructed summary.
- **Loop consequence:** the recommended sprint cadence (draft through `/work` + wrap, un-draft once for review) can now terminate CLEAN on cycle 0 with a genuine posted verdict — no independent-reviewer substitution needed for the "PR was clean on arrival" case.
- **Still true:** a SILENT run is never read as clean (all four silent causes in § Failure modes remain live). Clean **push-triggered** re-runs still read SILENT (skip-no-op); the post-fix-cycle clean confirmation is available via the **explicit `@claude review` retrigger** — see § calibration update 2026-08-26 below.

## § calibration update — an explicit `@claude review` re-review after a fix cycle DOES post a positive clean verdict (downstream, 2026-08-26)

Second field observation on the same canonical workflow (write perms + posting-tool allowlist + forced-summary prompt), this time on a large downstream PR (~3k net lines, 12 commits) that went through two fix cycles:

| Cycle | Trigger | Run | Posted |
| --- | --- | --- | --- |
| 0 | un-draft (`ready_for_review`) | `claude-code-review.yml`, ~7 min | `## Code review` — "No issues found." (0 inline) |
| 1 | fix push + `claude_retrigger.sh` | push run: `success` in ~70 s, posted nothing (skip-no-op); `claude.yml` (`issue_comment`) run: 3m42s | task-format comment "Claude finished … ### Code review … One gap I found …" — a real summary-body finding (0 inline) |
| 2 | fix push + `claude_retrigger.sh` | push run: skip-no-op; `claude.yml` run: **57 s** | task-format comment: "The gap I flagged … is fixed in `<sha>` … **No other issues found** … the rest … still looks correct." (0 inline) |

What this settles:

- **The clean re-review after a fix cycle is NOT structurally SILENT — it was the *push-triggered* path that SILENTs.** The 2026-06-03 "clean run → SILENT" observation and the 2026-08-18 "still true" caveat both watched the `synchronize` auto-run, which the plugin skip-no-ops once it has reviewed the PR. The explicit `@claude review` path runs the incremental review and **posts its verdict in the task format even when clean** (the checklist finalizes to all `- [x]` + a prose verdict). So the loop *can* terminate CLEAN after a findings cycle from this engine — the case IDEA-012 was opened for.
- **Read it exactly the way § Push-triggered model's mitigation says:** (1) the `claude.yml` (`issue_comment`) run for the head SHA is `completed`; (2) the task-format comment has **zero** `- [ ]` boxes (the in-progress placeholder has 5–7 unchecked and can trip the body classifier both ways); (3) the comment's `created_at`/`updated_at` post-dates the push; (4) zero inline comments on the head SHA. `find_claude_comments.sh`'s `CLAUDE_CHECKRUN` line is **stale** on these wakes (it reads the skip-no-op push run as `completed`) and its `LATEST_REVIEW` may still point at the cycle-0 summary — the adapter does not yet track the `claude.yml` run, so the orchestrator does this read by hand (`gh api …/actions/workflows/claude.yml/runs` + the issue-comment body).
- **Incremental scope is real and is fine.** The 57-second cycle-2 run reviewed the fix diff and re-asserted the unchanged parts by name ("unchanged since the last full review and still looks correct") — a verdict on the increment plus an explicit no-regression statement, which is what a post-fix re-review should say. It is not a second full-diff pass; the full pass remains the un-draft/first run (§ Incremental review).
- **Adapter follow-up (open):** teach `find_claude_comments.sh` to select the `claude.yml` run and the task-format comment for the head SHA after a retrigger, so `CLAUDE_CHECKRUN` / `CLAUDE_LATEST_REVIEW` stop going stale and the manual read above becomes unnecessary. Until then the § Push-triggered model mitigation is the contract.

## § calibration update — the push-triggered run can do a FULL re-review after a fix push, and catch what the retrigger missed (downstream, 2026-08-28)

Third field observation on the canonical workflow, one fix cycle on a ~3k-line docs PR:

| Trigger | Run | Posted |
| --- | --- | --- |
| fix push (SHA₂) + `claude_retrigger.sh` | `claude.yml` (`issue_comment`), **1 m 32 s** | task-format comment: "No issues found. Both findings from the prior review round are fixed …" (0 inline) |
| the same push's `synchronize` auto-run (`claude-code-review.yml`) | **~12 min**, `completed/success` **after** the retrigger verdict | a new `## Code review` summary + **2 inline findings** on SHA₂ — a real structural defect (`allOf` pattern conjunction) the fix had introduced and the incremental re-review had not seen |

What this settles — and partly reverses § Stale summary on a new SHA:

- **The skip-no-op after a first review is not guaranteed.** On this repo the push-triggered run reviewed the increment in full (it runs the project's checks first, hence the length) and posted findings; the explicit-retrigger run, scoped to "were the prior findings addressed", declared clean. Both are legitimate outputs of the same engine on the same SHA.
- **✅ DO wait for BOTH runs of the head SHA to be DONE before reading a verdict**: the `claude.yml` run the retrigger started *and* the `claude-code-review.yml` run the push started. `find_claude_comments.sh`'s `CLAUDE_CHECKRUN` line tracks whichever run is latest by start time, so a wake that sees the retrigger's clean comment while the push run is still `in_progress` is **RUNNING**, not CLEAN — the adapter's own gate held here; the orchestrator must not short-circuit it because a clean-looking comment exists.
- **Stale re-anchored inline comments still appear on the new head.** GitHub carried the fixed findings' comments (older `review <rid>`) onto SHA₂; the adapter listed them under "findings on the head SHA". Identify by `comment id` + `review <rid>` against `LATEST_REVIEW` (§ Staleness rule) — they are not active, and their threads were already resolved by the fix cycle.
- **Read the second review as a new cycle, not as a contradiction**: triage its findings, fix, push, retrigger, and again wait for both runs.

## § Failure mode — org Actions billing block (downstream, 2026-08-28)

A fourth infrastructure state that presents like an engine failure: **every** workflow run in the organisation — the test workflow, `claude-code-review.yml`, `claude.yml`, on every branch including pushes to the default branch — completes `failure` within seconds with a job that has **zero steps** (no runner ever started). githubstatus.com is all-green. The job's check-run annotation carries the cause verbatim: *"The job was not started because recent account payments have failed or your spending limit needs to be increased. Please check the 'Billing & plans' section in your settings"* (`gh api repos/<owner>/<repo>/check-runs/<job-id>/annotations`). `gh api /orgs/<org>/settings/billing/actions` needs the `admin:org` scope and is not the fast path — the annotation is.

Orchestrator action: the engine is **ERRORED**, not HUNG or STILL_FINDING — hand back with the annotation text; only an org admin can clear it. Do not retrigger into the block (each attempt is another zero-step failure). When the human reports it fixed, resume without a new push: `claude_retrigger.sh <PR>` (or `gh run rerun <run-id>` for the push run) — the fix commit is already on the head SHA. Local verification (`composer test` / the project's suite) is what the hand-back can vouch for in the meantime, and a status note on the PR saves the merger a guess.

## § calibration update — the reviewer says it "cannot run" the project's checks (downstream PHP project, 2026-08-27)

**Symptom.** The posted review reads *"I wasn't able to run `composer openapi` or the PHPUnit suite in this environment (no `vendor/` in the checkout)"* and defers to the PR description for verification. Not a muzzle (`permission_denials_count: 0`, findings posted) — the bot genuinely had nothing to run with.

**Three causes, all in the workflow / repo, none in the bot:**

1. **The review job never installs dependencies.** The action checks out the repo and starts the model; a fresh runner has no `vendor/` / `node_modules/` / venv. Add the language setup + install steps (`setup-php` + `composer install --no-interaction`, or the stack's equivalent) *before* the action step in **both** the PR-event workflow and the `@mention` workflow.
2. **The allowlist only names the posting tools.** Even with deps installed, `Bash(composer test)` is denied unless allowed. Extend `--allowedTools` with the exact verification commands (`Bash(composer openapi)`, `Bash(composer test)`, `Bash(vendor/bin/phpunit:*)`, `Bash(git diff:*)`, `Bash(git status:*)`), never a blanket `Bash(*)`.
3. **The mention path has no prompt.** The PR-event workflow's `prompt:` can say "run X and quote the output"; the `@mention` workflow has none, so a repo-root `CLAUDE.md` is the only channel that reaches both runs. Write it for *the reviewer*: "deps are installed before you start — run these commands and quote the output; a diff in the generated artefact is a finding".

**The vendor-churn misread.** If the repo tracks a partial `vendor/` snapshot, `composer install` rewrites and deletes tracked files, and `git status` after the install shows dozens of `M`/`D` entries under `vendor/`. A run under fix 1 still reported *"no `vendor/` in a usable state"* because it read that churn as a broken checkout. `CLAUDE.md` must say so explicitly ("expected and harmless — scope inspection with `':!vendor'`"). Once all three landed, every subsequent review posted its own `composer openapi` (zero warnings) / drift-check / `composer test` output before the findings — the reviewer became the verification, not a reader of claims.

**Adapter false negatives on a clean re-review (same window).** `find_claude_comments.sh` classes a task-format summary as *findings-bearing* by heading heuristics: a section titled **"Verification results"** or **"Prior finding — confirmed fixed"** is reported as `CLEAN=false FINDINGS=true` although the body ends in *"No other issues found"*. Read the body before acting on `CLEAN=false`; the true verdict is the prose, not the flag. (Candidate tooling fix: treat headings matching `Verification|confirmed fixed|Prior finding` as non-findings.)

## § residual open questions (post-downstream calibration)

The §131 + §140 downstream blocks supersede the PR #167 first-run calibration — identity (`github-actions[bot]` → **`claude[bot]`**), the dead "zero-inline-only, no summary" posting model, and `CLAUDE_BODY_SIGNATURES` wording are all now confirmed. Two items survive it:

- **Never calibrate "clean" off a read-only (`pull-requests: read`) run.** The PR #167 run read clean only because it had nothing to flag; read-only silently **cannot post**, so a *findings-bearing* read-only run would fail to post → false CLEAN. Fix is `pull-requests: write` + `issues: write` (§ Identity + onboarding reference).
- **Still open:** **Q2** — the `claude_retrigger.sh` `@claude review once` fallback is unexercised (the action auto-runs on push); confirm if a future auto-run fails to fire. **Q1** — whether inline findings share a `pull_request_review_id` is unobserved; the anchor keys on comment id either way (§ Staleness), so safe regardless.
