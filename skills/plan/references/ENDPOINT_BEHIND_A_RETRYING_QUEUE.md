# An endpoint that a retrying queue calls: the status code is the retry instruction

**Load when** a plan adds or changes an endpoint whose caller is a **queue worker**, not a person or
a synchronous client. That covers an async-HTTP task, a webhook redelivery loop, or a job runner
that "calls the URL until it works". This is the consumer side of
[`FAN_OUT_THROUGH_A_SHARED_SERIAL_QUEUE.md`](FAN_OUT_THROUGH_A_SHARED_SERIAL_QUEUE.md) and
[`AMEND_A_QUEUED_TASK_PAYLOAD.md`](AMEND_A_QUEUED_TASK_PAYLOAD.md), which cover the producer.

**Field case.** A backend delivered a changed consent flag to a legacy PMS-facing API as one queued
GET per record. Two things made the design hard:
- **The queue:** it counted **HTTP 200 as done** and never read the body. It retried every other
  status with `max_tries` set to "effectively infinite", so its give-up-and-alert branch could
  never run. It sent one task at a time.
- **The legacy API's own conventions:** its house rule said "400/404 for caller errors". Its
  framework turned an unknown action into an **empty 200**, and its bootstrap answered **200**
  when the database was unreachable.

Every one of those, read against the queue, was either a loop that never ends or a silent loss. A
clean single-endpoint design would have shipped both.

## 1. Read the consumer before you choose a single status

Before designing the endpoint's replies, answer these from the **consumer's code**, not its README:

| Question | Why it decides the design |
|---|---|
| What counts as done: `200` only, any `2xx`, or a body field? | Decides whether anything in the body matters |
| Is the body read at all? | If not, `success:false` inside a 200 is a completion, and the queue will not retry it |
| Which statuses retry, and how many times? | "Retry every non-200, unlimited" makes a 4xx for a permanent error an endless loop |
| What happens on a transport failure (connect refused, timeout)? | It is often *terminal*, not retried. That is a residual you cannot fix from the endpoint |
| Is the drain serial, and what is the per-task timeout? | One slow call stalls every unrelated task behind it |
| Is there a "max tries reached" alert? Can it fire? | With `max_tries = INT_MAX` it never fires, so a stuck task is invisible |

When there are two consumers (an in-process cron adapter and an external worker), read both. When
one is out of the workspace, quote its documented handler contract ("return 200 on success,
non-200 to ask for a retry") and mark the claim as documented, not measured.

## 2. Map every outcome to "done" or "retry", then pick statuses

| Outcome | Can a retry fix it? | Reply |
|---|---|---|
| The write happened | — | **200** |
| Nothing to do (value absent or invalid, already in that state) | no | **200**, success |
| Malformed id, record not found, target gone | no, the queued URL never changes | **200** with `success:0` and a fixed message |
| Wrong credential | yes, once the credential matches (§ 4) | **403** |
| Storage error after connecting (lookup or write threw) | yes, after recovery | **500** |
| Storage unreachable before the action runs (§ 3) | yes | **503**, from wherever that path lives |
| Unknown outcome (a new code path, a bug) | assume yes | **500** |

- **Put the mapping in one pure function** (outcome → status and body), and execute its truth table
  in the test. The action then only decides the order of checks.
- **Order the checks** so that a wrong credential never reaches storage, and so that "nothing to
  do" answers before the id is parsed.
- **The body is for humans and logs.** Keep the keys fixed, never echo input, and don't design
  anything that the consumer would have to parse.

## 3. The framework answers before your action does

The endpoint's status table is only as good as the paths that run **before** the action. List them
for the actual stack and read what each returns:

- **Unknown action or route.** Many legacy frameworks throw, and a top-level catch answers an
  **empty 200**. Until the endpoint is deployed, every queued call to it is silently "done". So:
  - **Deploy the consumer before the producer's switch is turned on.**
  - **Turn the switch off before any rollback of the consumer.**
  - Write both into the PR body and the runbook.
  - Before deploying, probe the endpoint and expect the "unknown" signature. That proves the probe
    can tell the difference.
- **DB connect / session init failure in the bootstrap.** A `die('database error')` sends 200
  unless it sets a status first. Add the 5xx there.
  - It changes the DB-down reply of **every** endpoint, so make it its own commit and say so.
  - Synchronous callers usually already treat the text body as a failure. Queued callers now retry
    instead of completing silently.
- **An uncaught exception reaching a top-level catch.** Same empty-200 shape. If fixing it
  fleet-wide is out of scope, give the new action its own `catch (Throwable)` that answers 500
  with a JSON body. Record the fleet-wide defect as its own item.

## 4. The queued URL freezes the credential

When the credential travels in the URL (a path or query `key`), the producer bakes it in **at
enqueue time**:
- Fixing the producer's key later does not repair the tasks already queued.
- **Rotating the consumer's key** turns every pending task into a 403 that retries forever, with no
  alert (§ 1) and the old key written to the access log on every try.

Write a rotation step next to the status rule: *drain or rewrite the pending tasks for this call
before rotating the key.* A 403 is still right for a wrong key: once the key matches, the retry
delivers the call.

## 5. A helper that swallows errors cannot signal "retry"

Reused "advisory" writers (log and continue, never throw) are right for their original callers,
and wrong for a queue-facing reply: "logged and ignored" becomes a 200 and a lost write.

- Make the helper **report** its outcome without changing its behaviour: `null` when nothing was
  attempted, the row count when it wrote, `false` when it threw.
- Existing callers ignore the return value. The new caller maps `false` to 500.
- Check what "0 rows" means on the actual database before you map it. Some engines count matched
  rows, others changed rows.
- It is a cross-IDEA amendment when the helper belongs to a shipped IDEA. Keep its signature, guards
  and log text byte-for-byte where tests pin them.

## 6. Write the residuals down

These are real, and most are not fixable from the endpoint:

- **A persistent error after connect retries forever,** one log line per try. A pre-deploy schema
  or column check is the mitigation.
- **A transport failure can be terminal in the consumer.** An unreachable endpoint may lose the
  task for good.
- **A serial drain plus a row-lock wait** in the endpoint stalls the tenant's whole queue for up to
  the task timeout.
- **Ordering.** A *retried older* task that completes after a newer one overwrites the newer value
  when the selector orders by id and keeps retry rows. Only the producer can fix that, with a
  version or timestamp guard. Name it in the hand-off.
- **Several writers, one field.** When the endpoint writes a field other paths also write, the
  latest call wins. Say which orders can overwrite a newer answer.

## 7. The project's written status rule

A house rule like "400/404 for caller errors" is correct for synchronous clients and wrong here. Don't
bury the departure in the PR body. Amend the rule text with a **general exemption** in the same PR:

> An action whose only caller is a queue that retries every non-200 answers a failure a retry cannot
> fix with 200 and `success:0`, and keeps 403 / 5xx for failures a retry can fix.

Cite it from the action's docblock. See [`WAIVED_RULE_AMEND_THE_SOURCE.md`](WAIVED_RULE_AMEND_THE_SOURCE.md).

## 8. Plan checklist

- [ ] The consumer's done / retry / give-up semantics are read from code (or quoted from its documented
      contract), per adapter.
- [ ] Every outcome is mapped to done or retry. The mapping is one pure function with an executed
      truth table.
- [ ] Pre-dispatch paths are listed (unknown action, DB-down, top-level catch), with what each
      returns. The DB-down path answers 5xx.
- [ ] The rollout order (consumer first, switch last) and the rollback order (switch off first) are
      in the PR body and the runbook.
- [ ] A key-rotation step sits next to the rule, when the credential is in the queued URL.
- [ ] Reused swallowing helpers report their outcome, and the new path maps a failure to 5xx.
- [ ] The residuals are written down, and the ordering one is handed to the producer.
- [ ] The house status rule carries the general exemption.

## Related

- [`FAN_OUT_THROUGH_A_SHARED_SERIAL_QUEUE.md`](FAN_OUT_THROUGH_A_SHARED_SERIAL_QUEUE.md): the
  producer side. It covers the drain's timeouts, single-flight, and what one bad target does to
  unrelated work.
- [`AMEND_A_QUEUED_TASK_PAYLOAD.md`](AMEND_A_QUEUED_TASK_PAYLOAD.md): changing what a pending task
  will send.
- [`LOCAL_FLAG_INTO_AN_EXTERNAL_RECORD.md`](LOCAL_FLAG_INTO_AN_EXTERNAL_RECORD.md): "presence is the
  signal", and one field fed from several writers.
- [`WAIVED_RULE_AMEND_THE_SOURCE.md`](WAIVED_RULE_AMEND_THE_SOURCE.md): amending the written status
  rule.
