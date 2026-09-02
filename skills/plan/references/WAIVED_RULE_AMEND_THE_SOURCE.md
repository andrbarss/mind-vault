# A waived project rule is amended where it is written — not noted in the PR

**Load when** a plan decision deliberately departs from a convention the project has written
down (a status-code rule in an API README, a "new endpoints must …" checklist, a naming or
response-shape rule in `CLAUDE.md` / `AGENTS.md` / `docs/`), because a legacy sibling, a
symmetric pair, or a product call makes the written rule the wrong fit for this one case.

## The failure

The plan records the waiver ("the 400 rule is deliberately not applied so the pair stays
symmetric with its legacy analogue"), the IDEA records it, the PR description records it — and
the **rule text itself is unchanged**. A review engine that checks "CLAUDE.md compliance" reads
the rule as written, finds the new code violating it, and posts a finding. The finding is
*correct*: a waiver that lives only in process artefacts (plan, PR body, commit message) is
invisible to anyone who reads the rule — the next reviewer, the next engineer, the next agent.
Field-observed: a clean first review, then a full re-review after a docs-only wrap push raised
exactly this, and a second fix-and-retrigger cycle was spent on a decision that had been made
before /work started.

## The rule

When a plan decision waives or narrows a written project rule, the plan's **Execution
Sequence gets a step** — in the same PR as the code — that:

1. **Amends the rule text at its source** with an explicit, general exemption: the condition
   under which the exemption applies (not "this endpoint"), what still applies (the parts of
   the rule that are *not* waived), and the first use. Write it so the next case can apply it
   without re-deciding.
2. **Backrefs the amendment** into the archive of the IDEA that authored the rule (the
   cross-IDEA-amendment contract), and names the amendment in the current IDEA's archive README.
3. **Cites the amended rule** from the code's own docblock or inline comment where the
   departure is visible, so a reader of the code finds the sanction in one hop.

The test at plan time: *"if a reviewer reads only the written rule and the diff, will they
flag this?"* If yes, the plan is incomplete until it schedules the rule edit.

## What is NOT enough

- A sentence in the PR description or the plan's Key Technical Decisions.
- A memory / auto-memory note ("user rule: …") — it does not reach reviewers or other machines.
- A comment in the code saying "deliberately not X" without the rule text changing — the
  comment documents intent, the rule still says otherwise.

## When the rule should NOT be amended

If the departure is a one-off hack the team does not want repeated, do not carve an exemption
into the rule; instead bring the code into line with the rule, or keep the finding open as a
tracked follow-up with the human's explicit acceptance. An exemption is for a *class* of cases
(here: "the mirror of a legacy lookup keeps the legacy lookup's empty-answer contract for the
shared key"), never for a single endpoint by name.
