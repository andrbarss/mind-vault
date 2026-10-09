# Replaying an effect the deferral window swallowed — after the deferred write-back

Load when a plan adds a step to a deferred-write worker (a job that registers a record in an external
system later than the request that created it) to redo an effect that a *second* writer attempted in the
window and could not complete because the record had no external id yet. Typical shape: the create was
deferred to a worker; a later request (a form save, an admin action) sends a child record to the external
system at save time, every adapter refuses the empty parent id, the child is marked locally as if sent
(complete / locked) with an empty external id, and nothing retries. The worker already replays the
effects *it* knows about (payment, confirm, the record's own tail) — the child records are the effect
nobody listed.

## 1. Eligibility = would-have-been-sent ∧ not-yet-marked, read from the rows

The save-time trigger is a predicate over the request (`is being locked`, `became complete`); the replay
has only the persisted rows. Write the predicate's **persisted form** — the columns the trigger set
(`locked = 1`, `confirmed = 1 AND NOT main`) — AND the "not yet sent" marker the save-time success would
have written (`external_id` empty). Then do a writer census: every code path that inserts or updates
those rows, and whether its rows satisfy the predicate. Rows a placeholder insert creates (unconfirmed,
unlocked), rows an import writes with the external id already set — list each as *not eligible* with
its reason. A second writer with the same trigger (the admin form) is covered by construction; say so.

Put the predicate in a pure static and table-test every flag combination plus the string forms the
database hands back (`'0'` / `'1'`).

## 2. The replay runs after the tail, inside its own catch — all of it

Order: write-back → tail → replay. The replay must not change the task's outcome (a child failure never
retries the parent's registration), so each send sits in a `catch (Throwable)` — `Throwable`, because a
`TypeError` from an adapter would escape the worker action's `catch (Exception)`, answer non-200, and
make the queue retry the whole task. **The same catch covers the part before the loop.** Resolving the
child rows (a factory, a list query) runs after the parent's write-back and tail have already happened;
an exception there is as fatal to idempotency as one inside the loop: the task repeats, re-enters through
the adopt path, and replays the tail a second time. Return one `failed` entry for the whole replay and
keep the outcome.

Return per-child outcomes (`sent` / `refused` / `failed` / `skipped_budget`) in the worker's result and
let the controller log them; the worker stays log-free if it was before.

## 3. Every ledger-asserted value the replay changes goes back to the ledger

A deferred worker keeps an idempotency ledger (the task payload) and, on retry, **re-asserts the ledger's
values on the parent row** (the adopt path writes `external_client_id = ledger.client_id`). If the
replay updates one of those values on the row — the main child's new external client id replacing the
one the create answered — and does not write it to the ledger, the next retry reverts the row while the
child row keeps the new id: a permanent parent/child mismatch every adapter reads off the parent. Rule:
after any row update of a column the adopt path asserts from the ledger, persist the ledger with the new
value (one more writer of the payload — name it in the ledger's documentation). Test it with a second
run whose payload carries the updated value: the write-back must assert the new id, and no further
ledger write happens when nothing changed.

Convergence on retry comes from the child rows themselves (a child whose id landed is no longer
eligible). The residual is one update wide: the external system accepted the child and the row write
threw — the child is sent again on retry. Accept it, say so, and carry the external id the system
answered in the `failed` message so an operator can reconcile.

## 4. A budget on starts when per-call timeouts exceed the worker's budget

Read the adapters' HTTP timeouts off their code before choosing a pause. Field case: a 2 s pause between
sends looked harmless against a 600 s worker budget, but the adapters' per-call timeouts were 360 s and
1240 s — one hung call already exceeds the budget, and N children × one timeout each would leave the
task stuck in progress, re-adopted after the guard window, and re-timed-out up to the retry cap, each
attempt holding every other task of the tenant's serial queue. The budget cannot interrupt a call in
flight; it can stop *starting* new ones. `GUEST_REPLAY_BUDGET_SEC` measured from the worker's entry (not
the replay's start), checked before the pause so an exhausted budget costs no sleep; children past it get
a `skipped_budget` outcome and are exactly what the operator's fingerprint query lists. Document the
pause slack the check-before-pause order leaves (a send can start up to one pause after the limit).
Pause before every send after the first **whatever the previous outcome** — a refusal was still a call.

## 5. Seams for a DB-free suite

Inject the child-row gateway (a factory object, like the worker's other seams), a sleeper and a clock as
defaulted constructor parameters. **Resolve the factory lazily**: its constructor may build a service that
binds a table, so an eager default needs a DB adapter on every construction — the skipped / "no external
registration" paths included — and the existing scenarios error on construction. Make the fake row
store's `save()` write into its own rows, so the retry scenario asserts the code and not a static fixture,
and make the fake parent store's update land on the row the next read answers, so "the send carries the
backfilled parent id" has teeth.

## 6. What the plan should say about the walk

The dev stack may never reach the worker: the producer records the deferred task only for a configured
engine, and the worker action may be disabled by env. Read both gates at plan time or the verification
section describes a walk that cannot run — see
[`../../work/references/WALK_A_WORKER_THE_DEV_STACK_NEVER_REACHES.md`](../../work/references/WALK_A_WORKER_THE_DEV_STACK_NEVER_REACHES.md).
A real external hand-over on a tenant with a provider is a `(human)` recorded follow-up unless a sandbox
tenant exists; the first production run is watched, and the fingerprint query (parent registered, child
eligible, external id still empty) finds what the replay left behind.

**Last Updated**: 2026-10-09 (captured from a deferred-registration worker that gained a child-record
replay; the two risks the independent review found — the pre-loop escape path and the ledger write for
the main child's new id — are § 2 and § 3).
