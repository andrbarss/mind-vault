# TOOL_INVOCATION_INTERPRETER — run a tool with its own interpreter, or it fails *plausibly*

A helper script invoked under the wrong shell does not usually crash. It runs, most of it works,
and the part that depends on shell-specific syntax quietly produces nothing. The script's own
error handling then reports that nothing — as a **legitimate-looking negative result**.

That is the dangerous shape. A loud failure costs a minute. A plausible empty answer gets
believed, written into a hand-back, and acted on.

## The failure, concretely

`tools/find_claude_comments.sh` starts `#!/bin/bash`. Invoked as `zsh tools/find_claude_comments.sh <PR>`
it printed:

```text
⏳ No claude activity yet for PR #<N> (no Actions run for the head SHA, no comments).
   claude is push-triggered (the action auto-runs on every push). If the auto-run
   didn't fire, bootstrap with the fallback: ./tools/claude_retrigger.sh <N>
```

while that PR had a **completed** `claude-code-review` run on its head SHA and four `claude[bot]`
comments, two of them findings. Re-run byte-identically under `bash`, it immediately emitted the
correct `CLAUDE_CHECKRUN=… STATUS=completed`, `CLAUDE_LATEST_REVIEW=…` and the finding blocks.
Reproduced on two separate PRs; not a race, not a timing artifact.

Why it degrades instead of erroring: the adapters use bash-only constructs — `[[ … =~ … ]]` with
`BASH_REMATCH`, `mapfile`, `${var,,}`, arrays indexed the bash way. Under `zsh` these do not
abort the script; they evaluate to empty. Every downstream filter then matches nothing, and the
"no activity" branch is the honest report of an empty pipeline.

## Why this is a false CLEAN, not a nuisance

Read the orchestrator's own rule: an engine is CLEAN when its check-run is DONE **and** zero
active findings match. A finder that returns "no runs, no comments" satisfies neither half — so
a careful loop treats it as `NOT_TRIGGERED` and fires a retrigger, burning a billed review. A
*less* careful reading — "the finder found no findings" — is a **false CLEAN on a PR that has
real, unaddressed findings sitting in it.**

The structural-clean rule protects against a bot's prose lying. It does not protect against the
*tool that reads the bot* returning empty for a reason unrelated to the review.

## The discipline

1. **Never prefix a script with a shell name.** Run `./tools/<name>.sh <args>` and let the
   shebang decide, or match it explicitly (`bash tools/<name>.sh`). `zsh script.sh`,
   `sh script.sh` and `bash zsh-script.sh` are all the same class of bug. On an interactive
   macOS host — where the login shell is `zsh` and the muscle memory is `zsh …` — this is
   easy to do by reflex.
2. **Check the shebang before the first invocation** of any tool you did not just write:
   `head -1 tools/<name>.sh`. One line, once per tool.
3. **Treat a negative result from a tool as unverified until the tool is known to have run.**
   When a finder reports "nothing found" on a PR you have reason to think is active, confirm
   against the API directly before recording it:

   ```bash
   gh api "repos/<owner>/<repo>/pulls/<N>/comments"       --jq 'length'
   gh api "repos/<owner>/<repo>/issues/<N>/comments"      --jq 'length'
   gh api "repos/<owner>/<repo>/actions/workflows/<file>/runs?per_page=100" \
     --jq --arg s "$(gh api repos/<owner>/<repo>/pulls/<N> -q .head.sha)" \
          '[.workflow_runs[]|select(.head_sha==$s)]|length'
   ```

   Two non-zero counts against a "no activity" report is the signature.
4. **When the two disagree, suspect your invocation before the tool.** The adapter is exercised
   on every loop run; a brand-new invocation style is the newer variable. Reproduce under the
   shebang's own interpreter *before* filing a tool defect — a wrong entry in a knowledge store
   costs more than the bug it claims to record. (Field case: this was written up twice as an
   "adapter false-CLEAN bug" and recorded in project memory as such, before a two-minute
   `bash` re-run showed the tool was correct all along.)

## The general rule

**A tool that cannot run should say so; a tool that half-runs will not.** Any interpreter
mismatch — shell, `python` vs `python3`, a `node` major version below what the script's syntax
needs — belongs to this family: partial execution, empty output, a plausible report of nothing.
Whenever a check comes back clean *and that is the answer you wanted*, spend one command
confirming the check actually executed.

## Related

- [`engine-adapter-contract.md`](engine-adapter-contract.md) — the marker stream the finders emit;
  an empty stream and a genuine no-activity stream are indistinguishable by shape, which is why
  invocation hygiene is the only defence.
- [`VERIFY_BOT_API_CLAIMS.md`](VERIFY_BOT_API_CLAIMS.md) — the sibling discipline for output the
  tool *did* produce.
- [`../SKILL.md`](../SKILL.md) § Phase 1 — "clean is structural, not prose"; this reference covers
  the case where the structure itself was never read.
