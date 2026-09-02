# A contract reversal after CLEAN is a re-verification, not a fix cycle

**Load when:** the loop has read CLEAN (or is mid-loop) and the user changes a *contract-level*
decision — a reader rule ("the flag is ignored" → "the flag hides the row"), a wire field, a
default, a status code — rather than asking for a fix to a finding. The temptation is to treat
it as one more fix cycle: patch the one line, push, wait. It is not one line. The old rule was
encoded in every artefact the sprint produced, and the review that cleared it cleared *that*
rule.

## What a reversal actually touches (the checklist)

Walk every one of these; each is a place the old rule was written down on purpose:

1. **The code path** — and any degrade path the change creates. A column that was "never read"
   and is now filtered in SQL needs its own degrade rung for tenants that lack it (an unknown
   column in a `WHERE` raises the same error as one in the select list); a flag that was never
   selected must stay never-selected if the wire shape is meant to be unchanged.
2. **Every pin that guarded the old rule** — they now guard the *wrong* thing and go red or, worse,
   stay green while asserting the opposite of the new contract. Invert them one by one; keep the
   route split (select route / filter route / wire route) so the new pins are as specific as the
   old ones were. Re-read the count: the suite should end at the same N unless a pin was added.
3. **Generated-artefact wording** — API descriptions that said "always emitted" / "never
   filtered"; regenerate the artefact and run the drift check (the first suite run after the
   change fails *only* on the drift guard — that is the expected signal, not a bug).
4. **The migration headers** (the *new* stem's up/down comments, never an applied file) and the
   migrations index row — they narrate the reader rule to the next DBA.
5. **The IDEA file, the plan, this repo's contract, the amended-IDEA sidecars, the index row** —
   add a dated *revision* section to the plan (which decisions it supersedes) rather than
   rewriting history; rewrite the contract's affected section with an explicit "differs from the
   original / the requesting contract" note; refresh the IDEA's status line and the reasoning
   fields that quoted the old rule.
6. **The runtime verification** — re-run it. Keep the earlier pass in the transcript when it
   proves something the new pass does not (the migration proofs), and label which pass proves
   the shipped reader.
7. **The PR body** — a reviewer reading "byte-identical response" over a diff that removes rows
   will flag the description, not the code.
8. **Cross-repo contracts** — if the old rule came from another repository's request, the
   reversal is a real amendment there; ship the paste-ready text as a hand-off (see the plan
   skill's `SCHEMA_CONTRACT_HANDOFF.md` § departure), do not edit a foreign in-flight branch.
9. **Architect findings that the reversal inverts** — a finding phrased as "name the *contrast*
   with sibling X" may become "name the *parallel* with sibling X"; re-read the integrated
   findings, not just the code.

## How the loop reads it

- Push the revision as its own commits (code, then docs) on the **same PR**; nothing is merged,
  so a new IDEA is ceremony without benefit.
- Treat the next engine verdict as **cycle 0 of a new contract**, not cycle N+1 of the old one:
  reset the scratch file's cycle log with a "contract revised" row, keep `commits_this_session`
  at its fix-cycle meaning (a user-requested reversal is not a review fix), and read the verdict
  structurally — run DONE, summary newer than the head commit, zero inline — never by the prior
  CLEAN.
- Under a push-triggered engine the reversal push may get a full re-review or a skip-no-op (the
  skip is non-deterministic; a substantive push after a clean first pass has been observed to
  re-review in full). If it skips and the explicit retrigger path is unavailable (mention
  workflow read-only), fall back to an independent reviewer subagent over the net diff, or a
  fresh PR from the same branch to force an `opened` full pass.

## Why it is worth writing down

The first pass had a CLEAN with the reviewer's own test output quoted. Everything *looked*
finished. A reversal at that point silently invalidates the review's premise while every
structural signal (green suite, drift-free artefact, posted clean summary) keeps reading fine —
until a pin asserts the old rule against the new code, or a consumer reads a description that
promises the old behaviour. The checklist is the difference between "changed the query" and
"changed the contract".
