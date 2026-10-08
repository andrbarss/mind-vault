# A value only the consumer's host knows, in a row another host will queue: name it, resolve it at the consumer

Load when a plan lets a **second producer** (another application, on another host) write rows into a
queue that an existing consumer drains, and the existing producer writes a value that is meaningful
only on the consumer's host. Typical shapes are an absolute template or upload path under the
consumer's document root, a local hostname or socket, or a file handle. The new producer cannot know
the value. It can only *say which one it means*.

## 1. Name it; don't spell it

- Give the consumer a **closed map of name → value**, computed at runtime from the consumer's own
  configuration (`document_root . '/…'`), never a literal path: the root differs per host and per
  deployment.
- The new producer writes the **name** from its own configuration. The map is the allow-list, and an
  unknown name resolves to nothing.
- One name per use (for example `cart` and `cancel`), even when they resolve to the same value today,
  so they can diverge without a producer change. Say in the contract whether cross-use is supported.
  Documenting it as unsupported keeps a later refusal from being a breaking change, without the cost of
  enforcing it now.
- The map is **not a security boundary** while the legacy key still wins (§ 2), because that key can
  still carry any path. The boundary is write access to the queue table. State it; don't imply more.

## 2. The legacy key wins unchanged; one resolver for every consumer

- `legacy key present → use it unchanged; else known name → resolve; else nothing`. Every row already
  queued and every in-repo producer is untouched by construction. Pin "unchanged" with an identity
  assertion.
- Put the precedence in **one** resolver that every drain of these rows calls, so parity holds by
  construction rather than by two copies.
- Keep the in-repo producers on the legacy key unless there is a reason to switch: a name-only row that
  a rolled-back consumer drains is refused or silently skipped (§ 6).

## 3. Decide each drain's outcome from the drain's own semantics

Read what the drain has already *done* when it needs the value:

- **The value gates the whole effect** (a mail drain that refuses missing data): an unknown name is a
  producer configuration error. End the row permanently (no retry) with its own message and one alert,
  ahead of the generic "missing data" check. The generic message would hide the typo.
- **The effect before the value is already committed** (a cancellation that completes before its
  notification): refusing or erroring buys a red status but never the notification. A retry stops at
  "already done" before it reaches the notification. **Complete the row and report the lost
  notification.** Only report when the notification was actually due, and pick a test row that
  discriminates that condition (the walk reference, § 6).
- Write down what happens when the **alert itself fails** (no mail transport): the drain's catch takes
  over, often turning `error` back into `repeat`. Put that in the contract, not in a reviewer's head.

## 4. New code ahead of a narrow catch must not be able to throw an `Error`

Drains commonly catch `Exception` (PHP), not `Throwable`. Anything that throws an `Error` past that
catch kills the batch, leaves the row claimed (`inprogress`) for good, and can hold the type's
"is a task running" lock until it times out.

- **No `array` type on the resolver** when it runs before the drain's own guard. A body that decodes to
  `null`, a string or a number then throws a `TypeError`. Leave the parameter untyped: `empty($row['k'])`
  and `$row['k'] ?? null` answer quietly for every non-array.
- **Gate a lookup key with `is_string` before `isset($map[$key])`.** An array key in `isset()` throws on
  PHP 8.
- **Read the row through `??` in log lines too.** A plain `$row['id']` on a JSON-*string* body throws
  `Cannot access offset of type string on string`. In the field this was a pre-existing crash in the
  drain's first log line, found only because the plan's claim "a non-array body ends 'missing data'"
  was checked against a string body.
- **Run a mutation pass over the guards you add.** An `is_array` gate in front of `empty()`/`??` survived
  every test, because those reads were already safe. Remove it and keep the non-array test rows as the
  pin.

## 5. The contract for the external producer

Emit it at plan stage (`SCHEMA_CONTRACT_HANDOFF.md`), final at the wrap. Per row type:

- **Which column carries the JSON.** Two row types of one queue can differ: one producer writes the
  body at insert, another inserts an empty row and writes the body into a second column afterwards.
  Name the selector's conditions on that column.
- The keys, the names, the precedence, and the dedup-key formula the existing producer uses (a second
  producer that builds it differently double-queues).
- **The retry cap.** A NULL max-tries means unbounded retries, with an alert per run on drains that
  alert in their catch.
- An outcome table: known name / unknown name / neither key, per drain, with the exact stored error
  strings.
- "Never write the legacy key from another host": it would be a path on the wrong machine, and it wins.

## 6. Deploy and rollback order

- The consumer deploys before any producer writes a name-only row.
- **Switch the external writer off before rolling the consumer back.** A pre-change drain refuses a
  name-only row, or skips its effect without a trace. Put this sentence in the contract and in the PR's
  deploy note, not only in the plan.

## Checklist for the plan

1. The host-local value, every producer that writes it, and every drain that reads it.
2. The closed name map, computed from the consumer's own root; one name per use; the cross-use rule.
3. One resolver: legacy key unchanged, else name, else nothing. Pin "unchanged".
4. Each drain's outcome derived from what it already committed. Alert-failure behaviour written down.
5. Nothing new ahead of a narrow catch can throw an `Error`: untyped resolver, `is_string` before a map
   lookup, `??` in log lines. Mutation-check every added guard.
6. The producer contract: columns, keys, dedup key, retry cap, outcome table, "never write the legacy
   key".
7. Deploy consumer first; writer off before rollback.

## Related

- `AMEND_A_QUEUED_TASK_PAYLOAD.md`: when a producer writes into a payload already queued.
- `ENDPOINT_BEHIND_A_RETRYING_QUEUE.md`: done / retry / give-up semantics read from the consumer's code.
- `SCHEMA_CONTRACT_HANDOFF.md`: the plan-stage contract for a codebase that consumes yours.
- `SMALL_OPTIONAL_PARAMETER_FOLLOWS_THE_ACTION.md` § 6: the type gate as the refusal, not a `catch`.
- `../work/references/WALK_A_BATCH_DRAIN_ON_A_PRIVATE_COPY.md`: verifying the drains without touching a
  shared database.
