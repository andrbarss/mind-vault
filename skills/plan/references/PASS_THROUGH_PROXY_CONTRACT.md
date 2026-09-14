# A pass-through proxy: validation follows the client's error renderer, and "verbatim relay" is a per-status-class claim

Load when a plan adds a field to — or documents — a write that an intermediate service forwards to another service without reshaping it (an admin API proxying a form to the system that owns the row, a BFF forwarding to a domain service, a gateway relaying a partner call). The plan will be asked two questions, and both have a measurable answer in code the plan can read before it decides.

## 1. Where the validator lives is decided by what the client can render

The tempting rule is "validate at the edge, in the shape the rest of the API uses." On a proxied write that rule can make the user's experience *worse*, because the client's failure path was written for the shape the **upstream** already sends.

Field case. The owning service answers a validation failure at HTTP 200 with `{success:false, errors:{reason:"<field>: <message>"}}` — one flattened string. The consuming form's failure handler renders `errors.reason` when a result exists and a generic "form filled incorrectly" text when there is none (any non-2xx: the framework's failure action never parses a result). A proxy-side `400 {errors:{<field>:"…"}}` — the intermediate API's house shape — would therefore have rendered the *generic* text; a `200 {errors:{<field>:"…"}}` would have marked the field but shown "error not specified" as the message. The upstream's flattened shape was the only one that form renders as a message. Decision: no validator on the proxy, one rule owned by the row's owner, the relayed shape documented verbatim in the UI contract.

The discipline, before adding any validator to a proxied write:

- **Read the client's failure renderer** (its `failure` callback, its `handleFailure`, the interceptor) and list the shapes it can turn into a message, a field mark, or both. This is a ten-line read.
- **Read the upstream's refusal shape** for the same failure class (the form validator's error envelope, the business refusal envelope). If it is already in the renderable set, a proxy validator is a second copy of the rule that changes nothing the user sees.
- **If the client renders a shape the upstream does not send**, that is a request for the *client* (a dialog-text change) or for the *upstream* (a per-field key) — write it into the contract as an open item, not into the proxy as a silent translation layer.
- **Say which it is in the contract**, with the renderer cited by file and line, so the next consumer does not re-open the question from "the rest of the API uses X".

## 2. "Returns the upstream body and status verbatim" is true for exactly the status classes the HTTP client relays

An HTTP client built without an error-passthrough option (Guzzle without `http_errors => false`, `requests` with `raise_for_status()`, axios without `validateStatus`) **throws** on every 4xx/5xx. If nothing on the proxy path catches, the framework's default handler answers the proxy's *own* 500 with the proxy's own body — the upstream's 500 body, its 404 body and its 422 validation body all vanish. The relay is verbatim for 2xx only.

- **State the relay by status class** in the contract: "2xx: body and status verbatim; non-2xx: this service's own 500 (existing behaviour)". The first draft of the field-case contract said "verbatim" and "the owner's 500 is not something this repo hides" — both false for non-2xx, both caught at architect review.
- **Do not fix it in passing.** The HTTP client is usually shared by every proxied action in the service; flipping error passthrough changes the contract of all of them and belongs to its own decision. State, pin, move on.
- **Pin both halves.** A fake upstream that records the forwarded call and answers a configured response: one test asserts the forwarded payload equals the posted payload key-for-key (the "no allow-list, no rewrite" claim), another feeds the exact upstream refusal body at 200 and asserts the proxy's response content is byte-identical (the "2xx verbatim" claim). Keep the fake's new recording surface separate from any list an existing suite asserts exactly (a `->posts` list beside `->calls`, not appended to it).

## 3. Name the exposure the pass-through inherits

A field added to a proxied write inherits every property of the path it rides: the route's permission gate (often only "authenticated"), the absence of an allow-list, and whatever the proxy logs on the way through — a request logger that dumps the whole POST records the new field on every save, and a second logger in the same call (a `var_export` in the controller plus a `print_r` inside the log service) records it twice. When the field is identity-class data, write the inherited exposure into the contract's permission/exposure section as a fact, and leave hardening (a gate, an allow-list, redaction) to its own decision — the pass-through plan is the wrong place to widen scope, and the right place to make the widening visible.

## Anti-patterns

- ❌ Adding a proxy-side validator "in the shape the rest of the API uses" without reading what the client's failure handler renders.
- ❌ "Returns the upstream body and status verbatim" in a contract for a client that throws on non-2xx.
- ❌ Flipping the shared HTTP client's error passthrough inside a single field's plan.
- ❌ A proxy test that asserts only the proxy's own 200 — pin the forwarded payload and a relayed upstream refusal.
- ❌ Recording new fake-upstream calls into a list an existing suite asserts as an exact sequence.
