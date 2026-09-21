# Producer argument contracts — classify at the branch, verify at the call site

Load when a plan **reuses a shared producer** (an availability loader, a rules engine, a price
query, a permission resolver) and passes — or deliberately omits — one of its *scoping
arguments* (`packet_id`, `tenant`, `authorized`, `children`, a guard key, an "include
inactive" flag). Two review rounds on one plan got the same producer wrong in opposite ways;
both errors have the same shape, and both are cheap to prevent with one discipline.

## The shape of the problem

A shared producer's scoping argument reads as an **additive filter** ("pass it and you get
less") until you read the branch. Three other shapes are just as common:

| shape | what passing the argument does | what omitting it does |
| --- | --- | --- |
| additive | narrows the result | the superset |
| **narrowing** (inner join / `AND col = ?` only `if ($arg)`) | the subset | **everything**, including rows that exist only for *other* scopes |
| **defaulting** (`intval(null)` → `0`, `isset(false)` → true) | the intended scope | a *wrong* scope — `< 0` excludes every rule with a threshold; a `false` default makes a guard clause always emit |
| **switching** (a non-null argument selects a different algorithm) | one code path | another code path — a recursion, an all-house pass, a cache bypass |

A plan that reasons "we'll call it packet-less and the answer is the superset" is right only
for the first row. On a narrowing argument the packet-less call applies **every** scope's rows
to every scope; on a defaulting one it silently excludes what it meant to include; on a
switching one it changes the cost or the semantics.

## The second error: reading the loader, not the call site

Once the narrowing shape is found, the natural next step is to design around it — subtract the
other scopes' contribution, add a second call, pre-load a scope map. **Before designing the
correction, trace the argument to the exact call site the plan will use.** A loader that
narrows on an argument is irrelevant if the function the plan actually calls never passes it
there.

Field case (generalised): a rules loader narrows on a scope id through an inner join. The
suspension builder the plan reused constructs that loader **without** the id — the id it
receives is forwarded only to a statistics helper. So the "packet-scoped" and "packet-less"
calls load the identical rule set; the residual is a different, smaller thing (the statistics
scope), and the subtraction the first review prescribed was both unnecessary and
unimplementable (the builder's index erases the attribution it would need). Two reviewers and
the author all reasoned from the loader's signature. One `grep` for the constructor call would
have settled it.

## The discipline

For every reused producer in a plan, in the *Context & research* section:

1. **List its scoping arguments** — every parameter that changes *which rows*, not just *how
   many*.
2. **Classify each by reading the branch**, not the docblock: additive / narrowing /
   defaulting / switching. Quote the line (`AND x = ?` inside `if ($x)`; `intval($x)`; the
   `empty($x) ? … : $this->recurse(…)`).
3. **Trace each to the call site the plan uses.** Is the argument passed through at all? To
   which callee? A narrowing loader behind a call that never forwards the argument is
   packet-independent by construction — say so, and stop designing a correction for it.
4. **State the residual's direction and size** — under-reports, over-reports, or neither — and
   make the verification probe's signal **vary** with it (a probe that reads the same value
   whether the residual exists or not is phantom verification).
5. **Name the baseline every cost claim excludes.** "Query count constant in N" is
   unachievable when the reused loader itself runs per-row reads (a category lookup per row,
   a localisation per row). Measure the loader alone at two sizes, then claim "constant beyond
   the loader's own per-row cost" — and assert exactly that in the probe.

The test for steps 2–3 is one question: *"if I delete this argument from the call, which line
of which function changes behaviour?"* If the answer is "none, because the call site never
passes it", the argument is not a contract on this path.

## The third error: forwarding a key the new target rejects

A **selecting** argument — a discount or promo code, a coupon, a campaign or affiliate id, a
price-list code — is compared against every candidate row, and the loop skips each row whose key
differs from the one it was given. Rows that carry **no** key (the automatic, default offers) are
often skipped by the same comparison. Callers written for the original target never notice: the
key was valid there. A plan that **re-runs the producer for a different target** (an upgrade, a
re-quote on another product, a transfer) and forwards the caller's key gets, when the new target
rejects that key, neither the keyed rows (the key is invalid there) nor the default rows (the key
excluded them). The price silently loses every automatic discount — and the response still
truthfully reports "code dropped", so nothing looks wrong.

1. When the plan forwards a caller-held key to a producer for a **different** target, read the
   comparison and state what the producer does with **unkeyed** rows when a key is given.
2. **Validate the key against the new target first**, with the same scope rules the producer
   applies (a consumed single-use code the caller owns, a channel) — and when it is rejected,
   **call the producer without it**, exactly as for a caller that never had one.
3. **The pre-check is the only validity answer.** The producer usually re-validates internally.
   When validation can call a remote service (a partner-validated code, a licensing server), two
   independent calls can disagree on a transient failure: the price is computed with the key while
   the result reports it invalid, and the key is dropped from a price that used it. Take validity
   from the check that decided what the producer was given, and override the producer's verdict
   with it.
4. **Verify with a target that has a default row and rejects the key.** Before the fix the price
   equals the undiscounted price; after it, the no-key price. A fixture target without a default
   row answers the same on both implementations — phantom verification.

## The fourth error: a switch in front of a narrowing argument flips every caller that passes it

The inverse job — *widening* a scope — invites the same one-read-short mistake. A service narrows
its list to the caller's scope when a scope was given (`if ($scope) { drop the others }`), and a
feature needs the whole list for one or two endpoints. The cheap, correct-looking design is one
switch in front of the comparison ("when the tenant opts in, skip the narrowing") — a single pivot,
every dependent method follows by construction. It is a good design. The plan's error is to list
the change by **feature surface** ("the cart total and the payment callback") when the switch acts
by **argument**: every call site that passes the scope flips, including the ones nobody was
thinking about — an admin screen whose SQL counts stay scoped while its totals now do not, a cron,
a mailer, a history page.

1. **Enumerate by argument, not by feature.** `grep` every call that *sets* the scope and every
   construction that does not; put the table in the plan — *site → what it does with the list →
   flips? → intended / accepted / pinned*. "Every action sets it" was false in the field case
   (twenty constructions, sixteen setters).
2. **Give the service an explicit pin** (`setWholeScope(false)`) and use it for the sites that must
   not follow — with a source pin that the call precedes the first dependent read. Leaving them
   under "out of scope" in the plan is not an exemption; it is an undeclared behaviour change.
3. **Callers that pass nothing are a contract too.** "No scope given = everything" is what the
   un-scoped callers (a partner API, a notifier) have always relied on; make it the helper's first
   rule and test it with the switch both on and off — and make the switch *unresolvable* for them
   (short-circuit before the lookup), so their load profile cannot change either.
4. **Look at how the narrowing was implemented before widening it.** A filter that `unset()`s from
   the instance cache cannot be widened after the first read, leaves holes in a list somebody
   indexes with `[0]`, and turns "cache the whole, answer a filtered copy" from a nicety into the
   fix. And do not "complete" the refactor by also resetting that cache in a neighbouring
   `clearCache()`: grep who calls it — in the field case a payment path called it between its
   amount check and its confirmation, and a re-read there is a time-of-check / time-of-use gap.
5. **Partial opt-in is a state to design for.** When the switch is per tenant and the data spans
   tenants, "A on, B off" is reachable: B's narrower payment marks its own rows paid, after which
   A's "basket already contains paid items" gate refuses the rest. Either make the group the unit
   (and say so in the go-live checklist) or make the mixed state coherent.

## Why the architect must do this, not just the author

The author reads the producer through the plan's intent ("we need the superset") and sees the
additive shape. The reviewer reads the loader's signature and sees the narrowing shape. Both
are one read short of the call site. The reviewer's checklist should therefore end at the call
site, not at the signature — the same `file:line` discipline that catches phantom
verification: cite the **call**, not the definition.

## Related

- [`VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md`](VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md) —
  the sibling for runtime-shape claims and phantom verification; this file is the static-read
  counterpart for reused producers.
- `agents/AGENT_architect.md` PASS 2 — the reviewer-side bullet that points here.
