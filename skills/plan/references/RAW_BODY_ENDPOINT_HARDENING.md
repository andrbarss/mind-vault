# A raw-body endpoint — the cap that runs after the read, credentials pushed into the URL, error text that multiplies the body

Load when a plan adds an action that reads a **raw request body** (a JSON document, a list of keys,
an XML payload) in a code base whose other actions read form fields — especially a bulk action that
validates many items and answers "one message per problem". Four traps, each of which passed a
competent plan, an architect review and a clean engine review before an independent reviewer or a
probe found it.

## 1. A size cap "before the body is read" that the argument expression defeats

```php
$result = Parser::run($_SERVER['CONTENT_LENGTH'] ?? null, $request->getRawBody(), …);
//                                                         ^ evaluated BEFORE run() starts
```

`run()` checks the declared length first — and the class docblock, the README and the test's
docblock all say "the size is pre-checked before the body is read". It is not: **a function's
arguments are evaluated before its first line**, so the framework has already pulled the whole body
into memory (often twice: a `trim()` copy for its emptiness test). The cap only saves the decode. An
out-of-memory fatal is not a catchable exception, so the client gets the web server's error page
instead of the JSON envelope the action promises.

- **Decide in the transport, before the read**: `$raw = Parser::exceedsCap($len) ? false :
  $request->getRawBody();` — and let the parser answer "too large" when handed `false` plus an
  oversize length, so there is one message either way. Cap the read string as well, for requests
  without a usable length (absent, chunked, lying).
- **Pin the order, not the presence.** A source pin that asserts the string `CONTENT_LENGTH`
  *occurs* passes on the broken build. Pin `strpos(cap-call) < strpos(read-call)` plus
  `substr_count(read-call) === 1`.
- Generalise: whenever a doc says a guard runs *before* an expensive or irreversible step, find the
  **expression** that performs the step and check it is lexically and dynamically after the guard —
  argument lists, default-parameter expressions, property initialisers and eager framework getters
  are where it hides.
- Size the claim to the stack: what the proxy and the runtime let through (`client_max_body_size`,
  `post_max_size`, `memory_limit`) bounds the real exposure. Say in the client contract that a
  proxy with a smaller limit answers its own 413 page, not your envelope.

## 2. No form fields → credentials and flags move into the query string → they are now in every URL logger

A JSON body does not populate the form-parameter bag, so everything that is not the document —
the API token, feature flags — travels in the **query string**. That is a contract fact the plan
must state (declare such flags as query parameters in the spec, say where credentials go). It is
also an exposure the plan must check:

- **Grep for anything that stores or emits the request URL**: access logs are expected; look for
  the unexpected ones — an "untranslated string" auto-logger that records the page it fired on, an
  audit table with a `page` / `referrer` / `url` column, error reporters, analytics beacons. If the
  action's path can trigger one, the token is now **at rest**, and any endpoint that publishes that
  table publishes the token.
- The containment that is in the action's own power: **nothing on its path may call the component
  that logs URLs** (write messages as literals, not through the translator), pinned negatively on
  the action *and on every class it delegates to* — the class that holds the message constants is
  exactly where a well-meant "localise the messages" edit would land. Verify after the live walk
  with a query for the action's own URL in the logging table.
- The containment that is not: other components of the same request cycle. Record the real fix
  (strip the query string at the logger, stop emitting the column) as its own work item instead of
  widening the plan.
- If the gate also accepts a **browser session**, a raw-body action with no media-type check is
  reachable by a cross-site `text/plain` POST; requiring the JSON media type forces a preflight.
  House parity with unchecked siblings is a legitimate decision — put it to the user and record it
  as a decision, never leave it as an accident.

## 3. Decode strictly enough to tell the shapes apart

- Decode with **objects as objects** (`json_decode($raw, false, <depth>)`): an associative decode
  cannot distinguish `{}` from `[]` or a list from a map on runtimes without `array_is_list`.
- The depth bounds nesting; **scalars count as a level** (`[{"k":"v"}]` needs 3). Choose the depth
  so that a wrongly nested *value* still decodes and is refused by the value rule with a useful
  message, while anything deeper is one generic "not valid JSON" — and pin the constant with a
  test, or the next reader "fixes" it.
- A successful decode guarantees valid UTF-8 (invalid bytes and lone surrogates fail), so text
  functions cannot return `false` later — but it does **not** guarantee the text fits the storage:
  refuse what the column would silently cut (characters outside its charset, byte lengths over its
  type). Duplicate properties inside one object: the last wins — decide it and pin it.
- Property names arrive as the client sent them: numeric names come back as integers from the
  object-vars call, the empty string is a legal name. Cast before echoing.

## 4. Error text that echoes the client multiplies the body

"One message per problem, each naming the item" is a good contract and a memory amplifier: a label
that embeds the **whole key** is repeated once per problem of that item, and unknown property names
are echoed uncut. One item with a half-megabyte key and a thousand junk properties fits inside a
1 MB body cap and builds hundreds of megabytes of messages — the same uncatchable fatal as § 1.

- **Cut echoed text** to a fixed character count (multi-byte safe, with an ellipsis), for keys and
  property names alike.
- **Bound the fan-out at the source**: an item with more properties than it could meaningfully
  have gets *one* message and is not enumerated; the answer carries at most N messages followed by
  a count of the rest. Capping only at the end still builds the full list first.
- **A clipped identifier needs a positional discriminator.** Once labels are cut, two long keys
  sharing a prefix produce byte-identical messages — a regression the fix itself introduces. Every
  refusal about an item should carry its 1-based position (`item 3 ("<clipped key>")`); messages
  that cannot (a post-write concurrency error reported by key) need a sentence in the contract
  saying what the client does instead (re-send).
- **Say what "every problem" really means.** Validators run in stages: body-level checks return
  early, item rules are evaluated for every item, a value reports its first broken rule, and
  anything that costs a database read (ownership) runs only for a body that passed the rules — so
  a request can be refused twice. Documentation that says "every item is evaluated, nothing
  short-circuits" is false of all of that; write the stages. Universal quantifiers in API text
  ("every", "always", "nothing") are the first thing to check against early returns.

## What the reviews looked like

Plan-time architect review: caught the URL-logger exposure and the unexecutable ordering tests.
Engine review of the finished PR: clean. Independent two-lens review of the same SHA: the
argument-order cap (both lenses), the error amplification, the over-narrow negative pin, the
overstated quantifiers. Independent review of the *fix* commit: the ambiguity the label clipping had
introduced, and wording the first fix had left inexact. None of these is visible to a suite that
is green; all of them were visible to a reader asked one narrow question — *"is this sentence true
of the code?"*
