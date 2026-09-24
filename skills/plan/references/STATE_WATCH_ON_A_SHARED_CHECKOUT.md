# A state watch on a shared checkout — per-tenant claims, date-qualified states, effects fired at most once

Load when a plan adds a **periodic job that reacts to a boundary the data itself does not record** — a
clock window opening or closing, a row entering or leaving a visibility range, a day rolling over — by
recomputing a small derived state every tick and firing effects (cache clears, events, outbound pushes)
only when that state changed. The shape is cheap and correct when four things are decided at plan time;
each of them was got wrong once in the draft that produced this note, and an architect pass rejected the
first version outright over the first.

## 1. Where the last-seen state may live

The naive store is a file next to the code (`cache/<job>.json`) or a process-local variable. On a
**multi-tenant checkout** — one code tree serving many tenants, the tenant picked per request from the
host header or an env file — a file is *cross-tenant* (every tenant reads the same "last state") and
*per-instance* (a second host has its own file). The state belongs in the tenant's own database, in a
small table keyed by the watched row: it is per-tenant by construction, survives restarts and
instances, and stays off every wholesale-emitted wire (`select *` on the watched row would publish a
column added there; a side table publishes nothing) and out of a mass-assigning admin writer.

## 2. What the state must encode — put the date in it when the meaning rolls over

Compute the state as a **string that changes whenever the effect must fire**. For a daily window the
obvious pair `open` / `closed` misses one boundary: a whole-day window is `open` at 23:59 and `open` at
00:00, yet the discounted unit moved from yesterday to today. Qualify the open state with the date —
`open@YYYY-MM-DD` — and midnight becomes a change like any other. Ask of every effect the job fires:
*is there a moment where the effect is due and the two-valued state is unchanged?* Each such moment is
a component the state string must carry.

## 3. The claim — one statement, the first contact decided on purpose

Fire an effect only after a **single-statement compare-and-set** admits the change, so overlapping
ticks (a second scheduler instance, a slow previous run) fire it once:

- unknown id → `INSERT IGNORE (id, state)`; affected 1 ⇒ first contact — fire **only if the inserted
  state is the active one** (an inactive first contact — "closed" on a row the job has never seen —
  changes nothing for any consumer; firing it clears caches for no reason on every fresh deploy);
- known id → `UPDATE … SET state = ?, modified = ? WHERE id = ? AND state <> ?`; affected 1 ⇒ fire (the
  inequality in the `WHERE` means the result does not depend on the driver's changed-vs-matched
  row-count setting — see [`COMPARE_AND_SET_GUARD_SCOPE.md`](COMPARE_AND_SET_GUARD_SCOPE.md) § 3);
- ids in the state table that the loader **no longer returns** (inactive, out of range, deleted) are
  claimed to the inactive state — they leave with their effects — and pruned after the effects ran.
  A row deleted outright may have lost its relations with it, so its fan-out is empty; say so.

Write `modified` from the application clock the state was computed on, not the database's `NOW()`
— on a stack where the two clocks differ (a UTC database under a local-time application) the
timestamps otherwise contradict the state.

## 4. The effects — at most once, and one failure never stops the others

The claim makes a boundary fire at most once. It does not make the effects run: a throw after the
claim consumed the transition and delivered nothing, and the next tick sees "no change". Decide the
recovery per effect, in the plan:

- **Build every collaborator before the first claim.** The notifier, the event manager, the channel
  clients — anything whose construction can throw (a registry key missing, a client reading config).
  A construction failure then aborts the tick with nothing claimed.
- **Isolate each effect** in its own `try / catch (Throwable)`; the notifier never throws and returns
  the failed count. One channel's outage must not undo the local cache clear or skip the next channel.
- **Roll back only a claim whose effects never started.** Keep the claimed `(id, previous, new)` list;
  empty it the moment the effects begin; the `catch` restores what is still listed. Restoring after
  effects ran would fire them twice on the next tick. This is the fan-out variant of
  [`CLAIM_BEFORE_SIDE_EFFECTS_NEEDS_A_WAY_BACK.md`](CLAIM_BEFORE_SIDE_EFFECTS_NEEDS_A_WAY_BACK.md): one
  release for "nothing ran", isolation instead of release once anything ran.
- **Name the fallback that recovers a single failed effect**, because the job will not retry it: a
  cache's expiry, a downstream's periodic full re-request, the next scheduled full export. If an
  effect has no fallback, it needs its own retry row — the watch is not the place.
- **Skip an off client before calling it**, and decide the outcome line by the client's own on/off
  predicate, not by its return value — one exporter here returned `false` even after a successful push
  and would have been logged as "off".

## 5. The lag the plan must state

The effect reaches each consumer after *its* cadence: an event that requests a rebuild is completed on
the next rebuild tick; a downstream that is only ever pushed by a half-hourly full export never sees a
window shorter than that cadence unless the watch pushes it directly. Enumerate the consumers, their
cadence, and whether the watch pushes them or merely invalidates them; a "within about a minute" claim
holds only for the consumers the watch pushes.

## 6. An un-migrated deployment is a normal state

New code reaches a tenant before its schema on any fleet that migrates per tenant. The loader's
unknown-column error must be caught and labelled (the two errno values for a missing column and a
missing table), answered with success (a cron endpoint that 500s once a minute is an alert storm),
and walked once with the migration rolled back.

## Verification — the walk rows

Seed one watched row and run the job by hand, reading the log line, the state row and the effect's
observable (a queued task count, an event listener's recording) after each tick:

| Precondition | Expected |
| --- | --- |
| fresh table, row active | first contact fires (state `open@today`) |
| unchanged | quiet tick, no state change |
| window closed a minute ago | fires `closed` |
| both bounds NULL | fires `open@today` (whole day) |
| state row edited to `open@yesterday` | fires `open@today` (**midnight**) |
| state row deleted while closed | re-inserted `closed`, **no** fire |
| state row deleted while open | fires once |
| row made inactive | fires `closed`, row pruned |
| still inactive | `0 loadable`, quiet |
| two ticks in parallel | exactly one fires |
| migration rolled back | "not migrated" log line, HTTP 200, no rows |

Plus a unit test through a scripted adapter for `claim()` / `restore()` (the SQL text and bound values),
and a notifier test with a throwing client (logged, counted, the next client still runs) — the live
stack rarely has credentials for every channel, so the failure isolation is proven in the unit test and
the guard path in the walk.

## Related

- [`CLAIM_BEFORE_SIDE_EFFECTS_NEEDS_A_WAY_BACK.md`](CLAIM_BEFORE_SIDE_EFFECTS_NEEDS_A_WAY_BACK.md) — the
  single-effect claim and its release; this file is the fan-out variant.
- [`COMPARE_AND_SET_GUARD_SCOPE.md`](COMPARE_AND_SET_GUARD_SCOPE.md) — the claim statement itself.
- [`VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md`](VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md) — "the checkout
  is per tenant" is exactly the runtime-shape claim to trace before choosing a state store.
- [`NARROWEST_CHANNEL_BOUNDS_THE_RULE.md`](NARROWEST_CHANNEL_BOUNDS_THE_RULE.md) — why the watch pushes
  the slowest channel directly.
