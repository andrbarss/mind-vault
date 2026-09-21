# A second, admin-writable source for a setting that was ops-only

Load when a plan gives a setting that lived **only in operator-controlled configuration** (an env key, a
config file on the server) a second source in a **data store the application can write** — a settings
table, a per-tenant properties row, a feature-flag document — usually "with higher priority, so it can be
changed from the admin". Load it with extra care when the setting decides something security-relevant:
where a credential is sent, which hosts are trusted, who is allowed.

The code change is small (read two values, prefer one). The work is elsewhere: the store already has
**readers that identify a row differently** and **writers nobody has listed**, and the moment you point a
reader at it, all of them become part of your feature.

Field case: a backend sent a fleet-wide shared key to every URL on an env-configured list
([`OPERATOR_LIST_THAT_RECEIVES_A_SECRET.md`](OPERATOR_LIST_THAT_RECEIVES_A_SECRET.md)). The owner wanted the
list editable per tenant: a row in the tenant's settings table, used instead of the env value when not
empty. Plan review, an engine review and two independent reviewers later, no defect was left in the code —
and the most important finding was a sentence in the operator page that put the human security check at
the wrong moment.

## 1. Precedence is a contract with more states than "A wins"

Write the truth table before the code, and get the owner's answer for every row — they are product
decisions, not implementation details:

| State | Decide |
| --- | --- |
| high-priority source set, low-priority set | **replace or merge?** Replace is easier to reason about ("what is in force?" has a one-row answer) |
| high-priority source set, but **every entry is refused** by the validator | fall back to the other source, or yield nothing? For a security setting: **nothing** — a fallback turns a typo into "the old list is silently back" |
| operator wants "none, overriding the other source" | it needs a spelling. Emptying the field cannot be it (empty = "not set" = the other source). Document one — e.g. a value that is valid but inert |
| high-priority source **cannot be read** (DB error) | **fail closed**: the code cannot know whether the admin replaced the other list. Set the memo *before* the read so the instance neither retries nor falls back |
| low-priority source not registered at all (a legacy config path) | the old early return (`if not registered: return`) must become "null"; a registry `get()` that throws on a missing key would otherwise fail closed on exactly the deployments the new source serves |

Implementation shape that kept this testable: a **pure chooser** (`pick(high, low) → {raw, source}`) in
front of the **unchanged validator**. Two details of the chooser earn their own tests:

- **"Not empty" must trim a superset of what the validator trims.** If the chooser uses a plain `trim()`
  and the validator splits on commas and skips empty pieces, a value of `","` is *set* for the chooser and
  *holds nothing* for the validator: the other source is off, nothing is accepted, nothing is rejected,
  nothing is logged. Sweep every single byte: "set for the chooser" ⇒ "at least one accepted or rejected
  entry", with the documented inert value as the only exception.
- **Normalise separators length-preservingly, and only for the source that needs it.** A textarea source
  wants newlines as separators; mapping `\r\n` to *one* separator shrinks the value, so a logged `length`
  and a byte cap stop referring to what is stored (a value one byte over the cap slips under it). Map byte
  for byte (`strtr`), and leave the other source's grammar alone.

Anything not blank is "set": a non-breaking space after a pasted URL, a BOM, a lone `0`. Say so on the
operator page — the symptom is "my env list stopped working".

## 2. Enumerate the store's writers — the gate sits where the exposure starts

List **every path that can write or create a row in that store**, not the paths your feature adds:

- the current admin (possibly another repository that writes the table directly);
- any bulk / API write path (does it authorise **by name or by type**? a row of your name with another
  type may be writable through it);
- **legacy CRUD screens** still routed in the codebase — generic "save a property" actions are the ones
  with the weakest gates and they accept *any* name;
- migrations, seeders, support scripts.

Then ask the question that moves the gate: ***can the row exist before anyone decides to use the
feature?*** If any writer has a create path — and generic CRUD always does — the row needs no migration
and no operator decision. If the reader resolves lazily, a write and the read can happen **in the same
request** (save → "push config" → the list is resolved *after* the save). The exposure therefore starts
when the **reader is deployed**, on every deployment where the feature's precondition holds, whether or not
anyone uses the new source there.

So a human check like "confirm route X is not reachable without a login" gates the **code deploy**. Written
as "before enabling the setting on a tenant" it tells the operator to skip the check exactly where it still
applies. In the field case this was the only major finding of the whole review, it was in prose, and it
was found by a reviewer who followed the legacy `save` action into the model's `create()`.

If the owner rules the weak writer out of scope, record three things: the check as a **deploy** gate in the
requirements, the follow-up that removes the need for it, and the recommendation to land that follow-up
first.

## 3. One comparator on every seam — reader, hider, migration

A settings table typically has a case-insensitive collation on the name and **no UNIQUE key**. Its existing
code identifies a row in several ways: a by-name reader using `=` (case-insensitive, first row), a publisher
folding rows into a map (byte-exact keys, last duplicate wins), an existence check reading that same map, an
API write matching byte-exact. Combine a case-insensitive **reader** with a byte-exact **hide filter** and a
row named `SETTING_NAME` is *used* as the setting and still *published*.

Pick one comparator — byte-exact is the one application code can also implement — and use it on **every**
seam the feature touches: the reader (`WHERE BINARY name IN (…)`, see
[`API_OWNED_ROWS_IN_A_SHARED_TABLE.md`](API_OWNED_ROWS_IN_A_SHARED_TABLE.md) § 4 for the index-friendly
form), the filter (exact key), and the migration's predicates
([`../../deployment/references/CONVERGENT_SEED_ROW_MIGRATION.md`](../../deployment/references/CONVERGENT_SEED_ROW_MIGRATION.md)).
A case variant is then consistently *somebody else's row*: not used, not hidden, not repaired, not deleted.
Verify it at runtime with an actual collision row, not only in unit tests.

Byte-exact does not settle **duplicates of the exact name**: a reader that takes the first row and a
publisher that keeps the last can disagree about which one is in force — and an empty duplicate in front of
a filled row silently hands control back to the other source, which defeats the kill switch. Either fail
closed on more than one row or document the hazard and the query that reveals it; decide it explicitly.

## 4. Hide it from wholesale emitters — at the emitter

A new row in such a table is published by every `SELECT *`-and-dump endpoint the moment it exists
([`WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md`](WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md)). For a
server-side setting that is a disclosure. Two rules:

- **Filter at the emitter, not in the shared list method.** The method that returns "all rows as a map" is
  often *also* the model's existence check on create / edit; hide a row there and it can be created a second
  time. A pure `strip(map)` called between the loader and the encoder, a source pin on that order, and a pin
  that the model does not mention the filter.
- **Deploy the code before the migration.** Migrating first publishes the row — and whatever an operator
  types into it meanwhile — until the filter is live.

If the filter class and the feature live in modules that must not depend on each other, repeat the name
literal and pin the two together from a test.

## 5. What moved with the source — write it down

Moving a setting from ops-only configuration into an application-writable store moves its **trust
boundary**, and rules written for the old boundary come along unexamined:

- validation rules that were reasonable for an operator ("internal hosts are fine") now apply to input from
  application users;
- weaknesses downstream of the setting that needed server access to trigger (a hanging target that stalls a
  shared queue, a failure notification that quotes a credential) are now reachable from the admin;
- is there an **audit trail**? Check who records *who* and who records *when* for that table — per writer,
  and **open the other repository** before writing "nothing records it";
- a process-level override of the old source still applies wherever the new one is empty.

State these on the operator page as consequences, file the ones you do not fix, and do not widen the change.

## 6. Observability

- The refusal log line names **which source** the refused entry came from; tests assert on the source name
  (assertions on the unchanged tail of the line prove nothing about it).
- Decide whether a *successful* pick is logged. If not, give the operator the query that answers "which one
  is in force?".
- When an old log line is reworded, living docs are updated from a **new capture**; historical records that
  quote the old form are left alone and get a backref saying what the line looks like now.

## Checklist for the plan

- [ ] truth table of precedence states, each answered by the owner (replace / merge, all-refused, "none", unreadable, unregistered)
- [ ] chooser pure and separate from the validator; emptiness ⊇ validator's trim; separator normalisation length-preserving and source-specific
- [ ] every writer of the store listed, with its gate and whether it can **create**; "can the row exist before anyone uses the feature?" answered
- [ ] human security checks phrased as gating the **deploy** when the answer is yes
- [ ] one comparator on reader, filter and migration; a collision row in the runtime walk; duplicates decided
- [ ] wholesale emitters found by container grep; filter at the emitter; code before migration
- [ ] what moved with the source: validation assumptions, downstream weaknesses, audit trail, overrides

## Related

- [`OPERATOR_LIST_THAT_RECEIVES_A_SECRET.md`](OPERATOR_LIST_THAT_RECEIVES_A_SECRET.md) — the validator this
  sits in front of; nothing of a refused entry is rendered.
- [`API_OWNED_ROWS_IN_A_SHARED_TABLE.md`](API_OWNED_ROWS_IN_A_SHARED_TABLE.md) — one comparator per concept;
  no UNIQUE key possible.
- [`WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md`](WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md) — the emitter
  is also a leak surface.
- [`../../deployment/references/CONVERGENT_SEED_ROW_MIGRATION.md`](../../deployment/references/CONVERGENT_SEED_ROW_MIGRATION.md)
  — the seed row, with predicates that match the code's comparator.
- [`../../work/references/EXECUTE_OVER_PIN.md`](../../work/references/EXECUTE_OVER_PIN.md) — a fake that
  lacks the forbidden method turns "use the exact reader" into behaviour, not a pin.
