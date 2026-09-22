# An identity parameter on a call that already carries a shared secret — context, never authorization

Load when a plan adds "who is calling" to every outbound call a class makes to another system — a
`backend=<host>` / `origin=<service>` / `tenant=<slug>` query key, a header, a body field — and the
call already carries a **shared credential** (a fleet-wide key, a service token, a webhook secret).
The change is small; the mistakes are in what the value *means*, where it comes from, and what
the consumer may do with it.

## 1. The value is the process's own identity — take it from where the process already records it

The call needs "which instance of us sent this". Do not derive it from the request (`HTTP_HOST`,
`SERVER_NAME`): the class also runs from cron and CLI where no request exists, and a proxy-facing
host is not the instance. Use the identity the process already **records about itself** elsewhere —
the configured host name that the job queue stores as each task's `source`, the service name in the
log context, the instance id in metrics. Reading the same key in both places makes the queued
task's `source` and the url's identity **agree by construction**; a second source (a new env key, a
constant) is a second thing to keep in sync and a second way to lie.

Read the value **once per instance**, in the constructor, through a guarded read (`isRegistered() ?
get() : ''`): the registry throws on an unknown key, a script may build the class before the config
loads, and the unit harness never loads it. Then check every shape the env reader can produce and
write them down: unset → `null`, `KEY=` → `''`, `KEY=true` → `'1'`, quoted values unquoted. The two
empty shapes must mean *no parameter*; the odd one (`'1'`) is sent **verbatim on purpose** — a
misconfiguration made visible on the wire beats one hidden by a normaliser. No lower-casing, no
port-stripping, no `parse_url()`: verify the fleet's real values first (every env file, not a sample) and
let the transport encode the value like any other.

## 2. Absent, never empty; one builder; unset-then-set

- **Absent, never empty.** `''`, `null` and "unregistered" all yield **no key**. A consumer that
  reads `backend=` as "unknown host" is worse off than one that sees no key; and "unknown" is
  already the meaning of the key's absence.
- **One builder for N sites.** A class with three places that do `params[secret] = token;
  build_query; concat` is three places to add the new key and three ways to drift. Collapse them into
  one `buildUrl(base, method, params)`; the review then reads one function, and the once-only pin
  (`build_query(` appears once in the class, the secret's assignment once) becomes assertable —
  see [`../../work/references/EXECUTE_OVER_PIN.md`](../../work/references/EXECUTE_OVER_PIN.md) § the
  constructor guard and the once-only pins.
- **Unset both keys before setting either.** The builder receives the caller's parameter array. In
  most languages an in-place overwrite **keeps the key's original position**, so a caller-supplied
  `secret_key` or `backend` would (a) sit ahead of the real ones — defeating the "credential first,
  identity last" order every pinned url relies on — and (b) pass through untouched when the identity
  is empty and the conditional set never runs. `unset(params[secret], params[identity])` first, then
  set; one test with a poisoned array, run with the identity present and absent.
- **Order is a pin decision, not a contract** — but decide it once (append last), so the existing
  pinned urls gain a constant suffix and a reader diffing a queued task sees the familiar prefix.

## 3. A header cannot reach a url-only queue

If the same call goes out synchronously *and* as a queued task whose adapter stores **only a url**
(`setUrl()`, no headers, no body), a header reaches the synchronous path alone. The query key is not
the elegant choice; it is the only one that reaches every path. Say so in the plan's non-goals so the
reviewer who asks "why not a header" reads the answer instead of filing it.

## 4. Caller-asserted identity is routing context, never authorization

The receiving side sees `secret_key=<fleet key>&backend=<host>`. **Any holder of the shared secret can
assert any identity** — the new key adds no authentication. Write the rule at every seam the consumer's
team will read: the operator runbook, the PR description, the solution doc. "The GUI may use it as
routing context only; it is never authorization." A consumer that later scopes a cache clear by this
key has a *routing* bug when it is wrong, not a security hole; a consumer that grants something by it
has built an auth bypass out of a convenience parameter. Distinct from — and additive to —
[`OPERATOR_LIST_THAT_RECEIVES_A_SECRET.md`](OPERATOR_LIST_THAT_RECEIVES_A_SECRET.md): that one is
about *which targets* receive the secret; this one is about what the target may infer from a value
that arrives beside it.

The drain / logger that already records full task urls with the secret (a known exposure, tracked
elsewhere) now also records the identity. A bare host adds **no new secret class** — say that in one
sentence and stop; do not let the review re-open the logging finding on this change.

## 5. The consumer is out of the workspace — gate the deploy, not the close-out

Whether the receiving system ignores an unknown query key cannot be read when its source is not in
the workspace. Do not close the IDEA on that unknown and do not block the merge on it either: make it
a **human pre-deploy probe** — one request from the producing server with the real credential and the
new key against a real consumer, expecting `200` (a `4xx` means the consumer's team goes first). Tag it
`(human)` in the requirements trace with "gates the deploy, not the close-out", record it in the
verification guide as the last section, and note that backend-first is safe once it passes (a consumer
that reads the key later loses nothing; one that never reads it is unaffected).

## 6. What the change makes false, elsewhere

The previous IDEA's docs said "the same parameters, the same `secret_key`" and "`get()` kept
byte-identical (md5)". Both are now false. **Date them, do not delete them**: the sentence stays as the
record of what that IDEA shipped, with `(true of IDEA-N; changed by IDEA-M)` beside it, and the
amending IDEA leaves a backref file in the amended archive. The quotes of old urls in captures and
verification guides are a historical record; a reader grepping a live log needs the new suffix, so the
solution doc says which form is current.

## 7. What to write down

- the value's source and every env shape it can take (§ 1), with the one verbatim oddity named;
- the once-only pins and the docblock rule (the new docblocks must not contain the pinned literals);
- the poisoned-array test and the absent-not-empty rows;
- the "context, never authorization" sentence, at every seam the consumer's team reads;
- the human pre-deploy probe and the deploy order;
- the sentences elsewhere that the change dated.

## Related

- [`NEW_PARAMETER_ON_A_LEGACY_ENDPOINT.md`](NEW_PARAMETER_ON_A_LEGACY_ENDPOINT.md) — the inbound
  twin: a new optional parameter on an endpoint *we* serve.
- [`FAN_OUT_THROUGH_A_SHARED_SERIAL_QUEUE.md`](FAN_OUT_THROUGH_A_SHARED_SERIAL_QUEUE.md) § 7 — the
  cheap way to see what every path actually sends.
- [`../../work/references/EXECUTE_OVER_PIN.md`](../../work/references/EXECUTE_OVER_PIN.md) — the
  constructor guard the harness never runs; once-only pins on the assignment form.
