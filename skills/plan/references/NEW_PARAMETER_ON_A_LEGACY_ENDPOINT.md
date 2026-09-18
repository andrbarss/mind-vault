# A new optional parameter on a legacy endpoint

Load when a plan adds an **optional request parameter** (a filter, a flag, a mode) to an endpoint
that already has callers, a documented always-200 (or otherwise non-conforming) contract, and no
test of its own. The work looks like "read two params, add an `if`". What it actually has to
guarantee is: *every existing caller sees nothing change* — and the project's written API rules
usually say nothing about this case.

## 1. Which contract does the new input follow?

Projects that modernised their API conventions typically have a rule of the form "**new** actions
answer invalid input with 400 and failures with 500; legacy actions keep their always-200
envelope until their own ticket". A new parameter on a legacy action falls between the two, and
an unwritten decision gets re-litigated by every reviewer.

Resolve it explicitly, with the user, as three separate questions:

- **An invalid value of the new parameter** — error status, silently ignored (legacy style), or
  coerced to an empty result? *Ignored* is the dangerous one for a filter: a typo returns the whole
  unfiltered payload and the client believes it is filtered.
- **An absent parameter** — must be the legacy behaviour, exactly.
- **An *empty* parameter** (`?flag=`) — this is a separate decision from "absent", and clients
  that build query strings from forms or nullable fields send it constantly. Decide it **per
  parameter**, say it in the parameter's description, and pin it. ("Null means all" from a
  stakeholder means *absent or empty* on the wire — confirm that reading, and decide what the
  literal word `null` does.)

Then **write the resolution into the project's rule text in the same PR** (see
`WAIVED_RULE_AMEND_THE_SOURCE.md`): the rule applies to *the path the new parameter opens*, and only
to it. A review engine enforces the written rule, not the plan.

## 2. If the success body is not an envelope, the status is the only discriminator

Legacy success bodies are often bare payloads — a map, a list. Adding `{success: false, errors}`
for the new error statuses gives the operation **two shapes**, and a client that checks
`body.success` breaks in the worst way when the payload is a map in which `success` and `errors`
are legal keys. So:

- do **not** retrofit a success wrapper onto a body existing clients parse;
- state in the operation description and in the rule text: *tell the outcome by the HTTP status,
  never by a key of the body*;
- say, on the 4xx / 5xx response descriptions, that only a request carrying the new parameter can
  receive them.

## 3. Leave the legacy path physically untouched

"Behaviour-preserving refactor" is a claim; "the old statements were not edited" is a fact.

- Read the new parameters **first**, decide *requested / not requested* with one pure predicate,
  and **branch out before the first legacy statement** into a method of its own. Everything below
  the branch stays byte-for-byte.
- The new method is not routable (private / not an action) — check the project's "every public
  action is documented" guard cannot see it.
- Read parameters through the same accessor the framework documents for the action ("POST behaves
  identically" is usually a promise already in the spec). Know its **source precedence** — route
  / path-style params, then query, then body is common — and that a *sibling* parameter handled
  elsewhere (a locale read by an adapter) may have the opposite precedence. Pin with requests, do
  not advertise beyond what was already documented.
- The new path gets the modern mechanics in full: catch the language's widest throwable, generic
  text on the wire, the real error in the server log, status set before the body, no view
  rendered.
- If the legacy path has a side-effect hazard (a logger that stores the request URL, credentials
  included), the new path must provably not call it — pin the negative on the transport method
  *and* on every class it delegates to.

## 4. Pin both halves at source level, and prove identity on the wire

No HTTP walk distinguishes "unchanged" from "rewritten to the same output today". Two pins:

- **Legacy half:** the legacy statements are still present **in order** after the branch; the
  action contains no status-setting call, no `catch`, no second encoder.
- **New half:** the transport literals (widest catch, status set, log call, no-render) in order
  around the one orchestrator call; none of the forbidden calls.

And one runtime proof: **hash the unfiltered response before the change and after it**, same
cache state, for each variant the endpoint has (each locale). Re-hash after the verification walk's
clean-up and on the final commit. Add the empty-parameter variants to the same table — `?flag=`
must hash identically to no parameter at all.

## 5. Spec and captures

- Document the new parameters, exactly the statuses the rule prescribes, and a dedicated error
  schema; keep the success schema as it was (widen only its *description*).
- Follow the house style of a sibling parameter for the schema type (an integer enum next to an
  existing integer-enum flag), even if the producer accepts the textual forms only — and record
  that as a deviation if the plan said otherwise.
- Capture-first still applies: filtered successes, the empty result, each 4xx form, and a *real*
  5xx (break one thing only the new path names — a column rename — never something the bootstrap
  reads). While the 5xx condition holds, show that a request on the *untouched* path — and one on
  the new path that does not need the broken thing — still answers 200.
- Re-derive the small captures (4xx, 5xx, empty) from the producer in a test, so a wording change
  cannot leave a stale capture behind.

## 6. Amended contracts elsewhere

A read added to an endpoint often falsifies a sentence in an earlier hand-off document ("there is
no dedicated list endpoint"). Grep the archives of the feature this one completes — especially
client-facing contract files — for the endpoint name and for negative-existence claims, and amend
them in the wrap with a dated note.

## 7. Hand-back wording — lead with what does *not* change

A compatibility caveat stated on its own ("a client already sending a parameter with this name
would now get a 400") reads as "this deploy changes behaviour for existing clients" and draws an
immediate, justified objection. Say it in this order:

1. clients that do not send the new parameters see **no change** — and how that was proven;
2. the only request that can get the new statuses is one that sends the new parameter with an
   invalid value;
3. the residual: a client that *already* sent an ignored parameter of that name — unlikely for a
   name invented today; grep the client repos you can reach and say which you could not.

## Plan checklist

- [ ] Invalid / absent / empty decided per parameter by the user; the literal `null` decided.
- [ ] The project's rule text gains the clause, in the PR, before or with the docblock that cites it.
- [ ] Status-only discrimination stated in the spec when the success body is not an envelope.
- [ ] Branch before the first legacy statement; new method not routable; accessor precedence pinned.
- [ ] Source pins for both halves; response hash before / after, empty-parameter variants included.
- [ ] Real 5xx through something only the new path names; untouched path shown alive meanwhile.
- [ ] Earlier hand-off documents grepped for sentences this change makes false.
- [ ] Hand-back leads with "nothing changes unless you send it".
