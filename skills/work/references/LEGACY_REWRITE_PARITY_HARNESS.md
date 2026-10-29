# A legacy ↔ rewrite parity harness — decided differences, known gaps, NOW CLEAN

Load when a step builds or extends a harness that sends the **same requests to a frozen legacy service and to its
rewrite** and compares the answers — the check behind a "copy the legacy logic exactly" decision, where the suite of
contract checks pins only part of what the legacy answers. Field-tested on two takeovers (a JSON booking API and an XML
PMS bridge); the second built its harness from the first's shape and the shape held.

## What one case does

```text
reset the mocks → arm the case's faults → send to legacy → read every mock journal
reset the mocks → arm the faults again  → send to rewrite → read every mock journal
compare → signatures → explain each one against the registries
```

- **Reset and re-arm per target, not per case.** A fault is often one-shot (`times: 1`); the legacy run consumes it, and
  the rewrite would otherwise meet the default answer and "differ".
- **Compare what each side sent, not only what it answered.** The mocks' journals (route, method, raw path, query, body,
  the outbound headers that matter) are half the contract: "what the service sends upstream" is business logic too.
- **Name the outbound headers explicitly — and include the ones the legacy HTTP library added on its own.** A legacy
  `CURLOPT_ENCODING => ""` makes libcurl send `Accept-Encoding` with every decoder it has; Guzzle 7 *suppresses* that
  header unless it is set, so a rewrite on Guzzle silently stops sending it. Measure the legacy request's full header
  set from the mock journal once, then decide each header: compare it, or record why not.
- **Canonicalise only what the decision says may vary.** For XML: drop whitespace-only text nodes, then C14N. For any
  other body: bytes. Anything wider (sorting, case-folding) hides differences nobody decided.

## Signatures, not values

The compare step emits `<field> <kind>` strings — `status value`, `content_type value`, `body value`,
`journal.<mock>.<i>.<field> value`, `journal.<mock> count` — never the values themselves. Values carry test
credentials and change with every fixture; signatures are stable and greppable.

A narrower signature beats a wider mask: when only the text of an error element may differ, emit `errors-text value`
(the bodies are equal once those texts are masked) instead of letting a `body value` entry swallow every body change.

## Two registries and one doc

| Registry | Lifetime | Each entry names | Removed by |
| --- | --- | --- | --- |
| `decided-differences` | permanent | case glob, signatures, **anchor**: a literal heading of the known-differences doc, which names the decision | a decision reversed |
| `known-gaps` | temporary | case glob, signatures, **owner**: the roadmap step whose work removes it | that step |

- **The anchor is checked**: the run fails when the anchor string is not in the doc. A decision cannot be cited by a
  section someone renamed or deleted.
- **A doc section no case can observe has no entry** (a constant-time compare that only differs for numeric
  passwords the test clients do not have): document it, but an entry would be permanently unused.
- **Headers outside the decision's compared set** are listed in the doc's introduction as "not compared", not as
  entries.

## NOW CLEAN fails the run

In a **full** run, every registry signature that matched nothing is printed as `NOW CLEAN — remove entry` and fails
the run. A filtered run (`ONLY=<glob>`) never reports unmatched entries.

This is not housekeeping. On its first run, NOW CLEAN caught a wrong premise written into the plan and the decided
entries: "the new framework's 404 page is `text/html`, the old one's `text/html;charset=UTF-8`" — both sides actually
sent the same header (the runtime's `default_charset` appends the charset to `text/*`). Without the rule the entry
would have stayed, masking a real content-type change later.

## A decided case still asserts the rewrite's own answer

When a decision makes the legacy side incomparable (a route dropped: legacy 500 with a trace, rewrite 404), give the
case an `app_expect` (status, content-type prefix) so it can still fail. And check every rewrite body for **trace
markers** (`Stack trace`, `#0 `, `.php:`, `Exception`) on every case, decided or not — a masked body is exactly where a
leaked trace would hide.

## Sending what the client library will not

PHP's `http` stream wrapper adds `Content-Type: application/x-www-form-urlencoded` to any request with a body. A case
named "no Content-Type" built on `file_get_contents()` therefore sends a form-encoded body (field-observed: the mock
recorded `application/x-www-form-urlencoded`). Send such cases over a raw socket (`fsockopen`, HTTP/1.0 so the answer
is never chunked), keep the wrapper case under its true name (`form-encoded`), and **verify the raw request once
against a mock journal** — "both sides answered the same" cannot show that the header was absent.

## A forwarded body the rewrite changes on purpose — and a signature nobody may decide

When a decision makes the rewrite forward *less* than the legacy (secrets stripped from a body it passes upstream),
a plain `journal…body value` entry would hide every other change to that body. Instead:

- **Compare after the harness's own strip.** When a forwarded body differs, remove the secrets from **legacy's** body
  with an independent implementation (a string search, not a copy of the app's regex) and compare the rest byte for
  byte; a match is the narrow signature `journal.<mock>.<i>.body without-credentials`. A whitespace or rewrite bug in
  the rest still shows as `body value`.
- **Make the unsafe outcome undecidable.** When the two bodies are *identical* while legacy's still holds the secrets,
  the rewrite forwarded them: emit `journal.<mock>.<i>.body credentials-forwarded`, and fail the run if any
  decided-differences or known-gaps entry lists a signature ending in `credentials-forwarded`. Without this, a case
  whose stripping broke reads SAME, and a glob entry still "used" by its sibling cases never goes NOW CLEAN.
- **Mutation-check it once**: make the running rewrite forward the raw body (an in-container edit), run the case,
  see `credentials-forwarded` fail it, recreate the container.

## Prove the harness can fail

Before trusting a green run, make it red three ways, once each, and revert:

1. remove an anchored heading from the doc → the anchor check fails;
2. add an entry that matches nothing → NOW CLEAN fails;
3. change one observable thing in the rewrite (a content type, inside the running container) → a `DIFF`.

## Checklist

- [ ] Reset + re-arm faults before **each** target; journals of every mock compared.
- [ ] Outbound header set measured from the legacy journal; implicit library headers decided.
- [ ] Signatures only; the narrowest signature for each decided variation.
- [ ] Decided entries anchored and checked; gaps owned by a roadmap step; unobservable sections have no entry.
- [ ] NOW CLEAN fails a full run, never a filtered one.
- [ ] `app_expect` on incomparable decided cases; trace markers checked on every rewrite body.
- [ ] Absent-header cases sent raw and checked against a journal.
- [ ] The three red runs done once.
- [ ] A body the rewrite strips on purpose: compared after the harness's own strip; an identical body that still holds
      the secrets is a signature no entry may decide; mutation-checked.
