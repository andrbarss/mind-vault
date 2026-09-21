# Fanning a call out to N targets through a shared, serial queue — measure the queue, not the request

Load when a plan turns "call one target" into "call one target **and queue the same call for N more**"
(additional domains, mirrors, regional replicas, webhooks) and the queue those calls ride is **shared
with unrelated work and drained one task at a time**. The design usually comes with a reassuring
sentence — *"the extra targets are queued, so a dead one can never delay the request"* — which is true
and answers the wrong question.

Field case: a backend told its storefront to drop caches; a second storefront domain was added, and the
decision was "the primary stays synchronous, the additional domains get the same call as a queued HTTP
task". The queue also carried the tenant's PMS sync triggers and payment callbacks.

## 1. Two questions, two measurements

| Question | Where the answer lives | How it was measured |
| --- | --- | --- |
| Can a bad target delay or fail **the request**? | the enqueue path | time the request with a hanging target listed — unchanged |
| Can a bad target delay **everything else on the queue**? | the drain | queue an unrelated task *behind* the bad one and watch whether it is delivered |

A verification step that only times the request passes identically in the good and the bad case — it
is phantom verification for the second question. Write the drain measurement into the plan.

## 2. Read the drain before promising anything

Find, in the consumer: is it **single-flight per type** (a "something is already running" guard that
skips the whole type)? what are the **connect and total timeouts**? does it **follow redirects**? does
the adapter **store a per-task timeout** at all, or does it drop the one you set? what happens on the
**last failed try** — a notification that quotes the task? In the field case: single-flight, a connect
timeout of "library default" (minutes), a total timeout of hours, no redirects, the default adapter
silently dropped the task timeout (a second adapter kept it), and the last failed try mailed support the
full URL including the credential.

That yields a failure-mode table worth putting in the operator page verbatim:

| The target… | Effect on the shared queue |
| --- | --- |
| is down (does not resolve / refuses) | its own tasks fail fast; nothing else waits |
| answers an error — *including a redirect the drain does not follow* | its tasks fail; one notification **per queued call** |
| silently drops the connection attempt | each of its tasks holds the queue for the connect timeout |
| **accepts and never answers** | **the whole queue stops behind it — the primary's own later calls included** |
| …and the drain process dies mid-task | the claim goes stale and keeps holding the queue after the target is gone |

Mark every cell **measured** or **by the code**. The stale-claim row is the one that gets overstated:
in the field case the write-up first said "nothing resets it", then "only the restart job resets it" —
both wrong; the claim also expires with the guard's own window, and a restart action for stale claims
already existed in the codebase and in its own reference doc. Grep for the recovery path before
documenting that there is none.

## 3. Fan-out creates producers that were never producers

The synchronous methods did not touch the queue before. After the change each of them writes N tasks —
and one of them ran on **customer traffic** (a cancellation, and an automatic expiry sweep with nobody
clicking anything). Inventory every call site of every method that now enqueues, and say in the docs
which of them are driven by end users rather than by an admin save: that changes who can trigger the
failure modes above.

Two dials worth offering the owner, neither worth deciding for them: a start delay on the additional
tasks so that one action's primary tasks drain first (ordering only — a hanging task still stops the
queue), and a lower cap on N (rows per action = calls × (1 + N)).

## 4. Opt-in per synchronous method, and a test that classifies every public method

Putting the fan-out inside the shared synchronous call path makes every current and future method fan
out — including the one that **reads the response**, which can only mean one target. Opt in per method
instead, and make the omission impossible to miss: a test that reflects over the class's public methods
and requires each to appear in exactly one list — *queues by itself* / *synchronous and fans out* /
*primary only* — with a source pin per list. A new public method fails the test until someone decides.
(Strip line comments before pinning: legacy classes carry commented-out calls.)

Keep the primary's code path byte-identical and prove it (hash the untouched method bodies before and
after every batch); resolve the target list lazily, not in a constructor that runs on every request.

## 5. "Nothing in the fan-out may throw" needs a probe of what it swallows

The right contract — the synchronous paths never touched the queue, so they must not gain a way to
fail — is implemented with a catch-all. A catch-all also hides the case where the fan-out **never
works**. Field case: on one queue adapter the queue model started a session on construction; in a CLI
script that printed before it enqueued, that threw every time, was swallowed by design, and the
additional targets would never have been called — no error, one log line. It surfaced only because a
fresh reviewer traced the construction path per *entry point* (web, API, each CLI script).

So: enumerate the entry points that construct the class, and for each one either execute the fan-out
once (a read-only probe of the bootstrap is enough) or state that it was not exercised. Log an
exception **class** and the target's host — never the message (it can carry the whole task, credential
included) — and make sure the logger itself cannot throw where its own prerequisites are missing.

## 6. What to write down

- the failure-mode table, with measured / by-the-code per cell;
- the **kill switch** (removing the entry stops *new* tasks) and what it does **not** do (tasks already
  queued are still tried — give the statement that retires them, and the existing stale-claim reset);
- the residual, stated as a residual, with the follow-up that owns the real fix (a per-task timeout the
  adapter stores, a connect timeout, the reset job scheduled everywhere).

## Related

- [`OPERATOR_LIST_THAT_RECEIVES_A_SECRET.md`](OPERATOR_LIST_THAT_RECEIVES_A_SECRET.md) — validating the
  list of targets when each accepted one receives a credential.
- [`VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md`](VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md) — phantom
  verification: a check whose signal does not vary with the thing it claims to test.
- [`REVERSIBLE_EXPIRY_ON_TWO_PHASE_HOLDS.md`](REVERSIBLE_EXPIRY_ON_TWO_PHASE_HOLDS.md) — another claim
  that outlives the process that took it.
