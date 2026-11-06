# Live check through the client's API: copy the client, and check the test data first

Load when a feature has to be proven end to end on a live test tenant by calling the backend
the way its user interface does (book → add items → pay → the integration fires), without a
browser. Also load when a front end reports an error and you need to tell a front-end fault
from a backend one.

## Copy the real client, not the API reference

The backend's API reference says what each action accepts. The front end's API client says
what the product actually sends. Read the client before the first call:

- **Call order and side calls**: e.g. list → price → reserve (with a cart id) → add each item →
  read the cart total → pay with that total.
- **Values the client makes up**: a cart or session id the front end generates (often a UUID).
  An action that marks it optional may still depend on it after its first write. Without it,
  the record is created and the request then fails. That leaves an orphan, which you have to
  find and clean up, and is worth an issue of its own.
- **Formats**: date and time layouts (`H:i:s`, not `H:i`), enum values (`service_type`), and
  per-item permissions. For example, an item may refuse a guest assignment unless its own flag
  allows it, so pick test items whose flags match what you want to test.
- **Verbs**: a route defined POST-only answers a GET from a browser address bar with the
  generic error page. "The page returns 500" can mean "it was opened by URL". Reproduce with
  the client's verb, session and CSRF token before treating it as an outage.
- **Response quirks**: an error page with HTTP 200; an answer object carrying `success: false`
  and an error string.

**Tell the layers apart.** Call each backend action the front-end action uses, with the same
parameters. All 200 with data → the fault is in the front end. Find which input varies: for
example, the items that fail are the ones with availability to render.

## Before the live check, check the test tenant's external mappings

A refusal from the external system ("no prices for this room and party", "product not found")
can be stale test data, not your change. Check these before blaming the code:

- **Rate / price codes** on the test catalogue: a code can have an end date ("valid until …")
  and still be listed by the partner. A test date after it can never price.
- **Room / product mappings**: a local type mapped to a partner type the partner does not sell
  online. Compare the partner's room list with what its price call returns for your dates.
- **Versioned identifiers**: an id with a date or version suffix that changes on the partner's
  side may go stale while the thing it names is still valid. Ask the partner whether the suffix
  is part of the key.

Pick a combination the partner prices for the test dates (a recorded successful partner call is
the best evidence), then run the live check. Changing a test tenant's mapping is the owner's
decision. Propose it; don't make it.

## Read the result from the integration's own log

- Decode the outbound call: the parameters, the nested arrays, and the partner's per-line
  verdict (created / skipped). Don't stop at the top-level `success`, which can be true while
  every line was skipped.
- A "refused, sent again without the optional part" fallback shows up as **pairs** of calls.
  When a retry loop runs, count the pairs before suspecting a second caller.
- Look for calls you did not expect (a payment write-back sending an update): check that they
  leave your result in place.
- Read and print the log through
  [`READING_PRODUCTION_LOGS_WITHOUT_LEAKING.md`](../../deployment/references/READING_PRODUCTION_LOGS_WITHOUT_LEAKING.md).

## Clean up what the live check made

- **Records that reached the partner**: list them for the partner to inspect, then cancel.
- **Records stuck on your side** (paid, never accepted): the public cancel action usually needs
  a cancel code or an owning customer, which test records lack, so plan an admin-side cancel.
  Paid test records retry until their task gives up.
- **Orphans from failed calls**: unpaid ones usually expire. Check that they do.

## Related

- [`WALK_A_WORKER_THE_DEV_STACK_NEVER_REACHES.md`](WALK_A_WORKER_THE_DEV_STACK_NEVER_REACHES.md) — the dev-stack counterpart of this check.
- [`DEPLOY_TARGET_MAP.md`](../../deployment/references/DEPLOY_TARGET_MAP.md) — make sure the test tenant's host runs the release first.
