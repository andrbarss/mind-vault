# Consuming a plan-stage contract — loaded-gated clearing keys, re-read at `/work` end, envelopes verified against the producing code, the claims the contract makes about *your* codebase, wire booleans, invariant handlers under a programmatic set, the failed-save residue of a gated key, a provisioning-probe route, and a partial-success envelope the client cannot decide

Load when a plan builds **against** a contract another codebase emitted at *its* plan stage — the consumer side of [`SCHEMA_CONTRACT_HANDOFF.md`](SCHEMA_CONTRACT_HANDOFF.md): an admin-UI write-side coded ahead of the API, a client built from a sibling service's draft, any "shapes are authoritative as intent, re-verified at the owner's `/wrap`" arrangement. Nine disciplines. The first three were field-caught on one idea (the first destroys data); §4 and §5 came from a later consumer of a contract whose §2 was an explicit *build spec* for the consuming repo — the richer the contract, the more of its prose is inference about code its author cannot run.

## 1. A `[]`-means-clear write key is a positive statement — gate it on the reference list having loaded

The contract shape that bites: key **absent** = nothing changes, `[]` = **clear every value**, non-empty = replace. The consumer draft derived the key from a *reference list* (the catalogue of things a value can attach to) that the form loads asynchronously after it opens, and reasoned about the one case where an empty list makes `[]` harmless — a degraded tenant with no rows at all. Two other cases produce the same empty list and are **indistinguishable on the client**: the list has not answered yet (the user edits an unrelated field and clicks Save on a slow tenant) and a transient load failure (timeout, 500, an auth race). Both serialise `[]` and wipe every value on the record. The architect pass caught it; every spec was green on the broken design, and the verification walk asserted the harmful behaviour as the expected one.

The rule: a key whose emptiness is destructive must never be computed from a list whose emptiness is ambiguous. Three parts, all needed:

1. **Derive the payload from state the component owns** — seeded from the record's own read-back and extended by the user's edits — never from the reference store. The reference list only says which ids are *active*; it is not the source of the values.
2. **A loaded-gate set only on a successful load** (`success !== false` on the load event, never "the store is non-empty"). While the gate is closed the editor is read-only and any "add" affordance is disabled — the user must not be able to edit what cannot be saved.
3. **An absent branch.** The payload builder returns `undefined` while the gate is closed and the host sets the key **only for an array**. Not loaded serialises as *absent* (= untouched), never as `[]`. `[]` is emitted only when the list loaded successfully and there is genuinely nothing to send.

Spec the three empties separately, because one green row hides the other two: loaded-with-zero-rows → `[]`; load answered `success:false` → `undefined` and the host's writer payload has **no** key; load never answered → `undefined`, then present once it resolves. Add one runtime row that throttles the reference request and Saves immediately — the body must carry no key and the values must survive a reopen.

The tell in a draft plan or spec: any row that asserts `[]` as the *expected* output of an empty list. Treat it as a finding, not a test.


**A fourth part: undo the residue of a failed save.** A dirty-tracking client model commits only on a
successful save. After a validation failure, or a partial-success answer that keeps the edit open, the
value set while the gate was open is still *modified*, so the next save carries it. That holds even
after the gate has closed and the UI has told the user the values will not be saved.

Field case:

1. Tick two targets, then save. The save fails with a 400 on an unrelated field.
2. Untick one target.
3. Reload the reference list, and the reload fails.
4. Save again. The body still carries both ids, and re-adds the one the user removed.

When the builder returns "absent", the host must *restore* the key's original value, which drops the
modified entry. Merely skipping the set is not enough. Spec it as one sequence on one record: open
gate, failed save, closed gate, save, and no key on the wire.

The same field case showed a second reason never to harvest the reference list: a filter hides rows
and the producer may exclude ids, so a harvest silently un-ticks both.

## 2. The contract is a moving target until its owner's `/wrap` — re-read it at the end of `/work`

A plan-stage contract is authoritative *as intent*. Its owner corrects it against their code as their `/work` lands — often the same day, in an uncommitted working tree, with no notification to the consumer. Field case: the single-record read envelope changed root key between the plan read and the consumer's PR (from the collection key to the key the sibling endpoint already used). The consumer's model reader was coded against the draft; the edit window would have opened **empty** on the first real run, and no spec could catch it because every spec stubs the proxy.

Before opening the consumer's PR: `git -C <producing-repo> status --porcelain -- <contract-path>` and `git log` on the file; if it moved, diff it against the version the plan cited and walk every `D`/`Q` that quoted a shape. Record the re-read in the plan's execution log with the contract's commit or "uncommitted working tree as of <date>". The plan-stage status banner on the contract is the reminder: it says the shapes are re-verified at the *owner's* wrap, which is after the consumer built.

## 3. When the runtime walk is blocked, verify the envelopes against the producing code

Consumers of a plan-stage contract routinely end with "runtime verification pending — needs a backend on branch X" because no environment serves the producer's branch. Do not leave the open questions as questions. The producing code is on disk: grep the controller and services for each shape the plan depends on and record the answer with `file:line` —

- the **root key** of every envelope the reader is configured for (single read vs collection vs create — they differ more often than contracts admit);
- how a **confirm / force flag** is read (`filter_var(..., FILTER_VALIDATE_BOOLEAN)` accepts `false`; a presence check does not);
- whether **empty-string** locale / optional fields map to NULL or are rejected;
- whether a **write key is collected on create as well as update** (a contract that documents only `PUT` leaves the `POST` path to guesswork, and one shared save path sends the key on both).

Each verified item flips its `Q` to "✅ verified in code (`Controller.php:NNN`)"; each divergence becomes a message to the contract owner and, when the consumer must change, a commit before the first review run. This is the consumer-side twin of [`VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md`](VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md): the runtime claim you cannot observe is checked at its source, not assumed from the document.

## 4. A contract that describes *your* codebase is making inferences — verify them like any other claim

The best contracts go beyond shapes and hand you a build spec: the exact field config, the model declaration, the error wiring, "here is what your framework will put on the wire." That generosity is worth having, and it carries a hazard the shape sections don't: **those passages are assertions about a codebase the contract's author does not run.** They were written by reading your framework's docs, or by reasoning from your last integration. They are the least-reviewed prose in the document, and a consumer who trusts them inherits a false premise directly into their plan.

Field case. The contract stated, as settled fact, that a locale whose editor tab is filtered out of the UI "is never constructed, so its key is never posted — absent means unchanged." True on **update**. False on **create**: the framework's default writer forces write-all for a new (phantom) record and iterates the **model's** declared fields, not the rendered form's — so the disabled locale's key ships anyway, as an empty string. The consuming repo already had this written down in its own solved-problem notes from an earlier idea; the contract's claim contradicted it. The consumer's plan had copied the claim into a "verified, read not assumed" table before the architect pass caught it.

The discipline:

- **Sort the contract into shapes vs claims-about-me.** Envelopes, keys, status codes, error values — those are the author's own code, trust and verify per §3. Anything phrased as "your X will do Y" is a hypothesis.
- **Grep your own framework / prior art for each such claim** before it enters your plan. Serialisation defaults, create-vs-update divergence, lifecycle ordering and "this never reaches the wire" are the usual suspects — a create path almost always serialises differently from an update path, and contracts routinely document only the update.
- **A claim contradicted by your own solved-problem notes is a defect in the contract, not a puzzle.** Report it; do not code around it and do not quietly correct only your own copy — the next consumer reads the same sentence.
- **Pin it with a test that would fail if the claim were true.** The cheapest form asks your serialiser directly what it would send for a fresh record and for a one-field edit, with no server and no DOM. That test is also the guard on whatever field-declaration choice the divergence forced.

## 5. An inherited acceptance criterion may be unobservable in your client — replace it, don't copy it

Contracts often close with acceptance criteria, and they are written from the **producer's** vantage: "do X, and the API's message appears on the field." Some of them cannot happen in your client at all, because something upstream of the network short-circuits first. Copied verbatim into your verification section, such a row is worse than a missing test — a human walks it, sees *a* plausible signal, and ticks it.

Field case. The criterion was: paste an over-long value, save, and "the backend's message shows on the field, the tab is marked, nothing is saved." In the consuming client the save handler is `if (form.isValid()) { … }` with **no else** — a client-side length rule fails first, so the request is never issued. Everything the criterion describes as evidence of correct server behaviour (a red field, a marked tab, nothing saved) is produced entirely locally. The row would read green against a correct backend and against a backend that had no such validation at all.

The discipline, per inherited criterion: **name the signal, then ask whether this client can physically produce it.** If the answer is no:

- **Replace the row with what the system can produce**, and make the replacement discriminating — here, the client message *plus* the marked tab *plus* **zero network requests**, asserted with a request spy. The zero-requests clause is the part that varies with correctness.
- **Say in the plan that you replaced it, and why.** A silently-dropped criterion looks like an oversight at review time; a replaced one with a one-line rationale is a decision.
- **Tell the contract owner.** An unobservable criterion is a defect in their document — they will hand it to the next consumer unchanged.
- Watch for the second-order consequence: when a client-side guard makes the server's message unreachable, that guard's **own** message becomes the only thing the user ever sees for that failure. It inherits the quality bar (wording, localisation) the server's message was holding.

## 6. Wire booleans are read through a truth table, never truthiness — the producer's own cast tells you why

The contract promises JSON booleans on the read-back, and the producer keeps that promise with a cast — `(bool) (int) $row->flag` — because its DB layer hands a `TINYINT` back as an int *or a string* depending on driver settings. The consumer's draft read the flag with `!!row[key]`, which is one character away from correct and reads the string `"0"` as **true**. The write side of the same contract listed the accepted encodings (`true | false | 1 | 0 | "1" | "0"`); that list is the tell that the read side can carry the same forms, and a flag that the client re-sends on every save turns one wrong read into a persisted wrong value — with the UI's own indicators confirming the corrupted state.

The rule: **one reader function, an explicit truth table, driven by the same field list every seed / commit / payload loop walks.** `true | 1 | "1"` ⇒ true; `false | 0 | "0"` ⇒ false; absent or `null` ⇒ the documented default; anything else ⇒ the default (the producer refuses those on write, so a read of one is drift, not data). Never `!!`, never `== true`. Spec the string forms, not only the numeric ones — a `1 / 0` row passes `!!` and proves nothing. Then, at the §3 static read, confirm the producer's cast (or its absence) in its own serializer: a guard's shape is validated against the producer's real data, never a mock (the self-sweep rule's defensive-code trigger). Precedent worth copying: a client that already reads a sibling flag strictly (`row.active !== false`) has the idiom on the same screen — reuse it.

## 7. A programmatic multi-field set must never reach the invariant handler — prove it with an event spy and a positive control

When N fields carry an invariant enforced by a `change` handler ("at least one on", "mutually exclusive", "sum ≤ limit"), loading a record sets the fields one at a time and **every intermediate state can violate the invariant**. The handler fires mid-load and "repairs" the record it was given: with three checkboxes showing `(on, off, off)` and a load of `(off, off, on)` that sets the first box first, the intermediate is all-off, the handler re-ticks the first box, and the loaded record is silently altered — the next commit persists the repair as if the user had asked for it.

Two parts to the fix, and the second is the one that gets missed:

1. **Set under suspended events** — the framework idiom the same screen already uses for its text fields (`suspendEvents()` / `setValue()` / `resumeEvents()`, or the equivalent).
2. **Hoist the set above any per-type branch.** The existing idiom lived inside the branch for one card type only; copying it literally would have left the other type's card showing the *previous* record's flags, and the next tick would have committed them into the wrong record. Before copying an idiom, check where it *lives* — a branch-local idiom is a statement about one branch, and the reviewer's spot-check of "the code sets the fields exactly as it does the text fields" is what caught it.

Proof — **never a transition assertion.** With three or more fields no single transition is set-order-independent: set the last field first and `(on, off, on) → (off, off, on)` never passes through all-off, so a spec that asserts "load this over that, map unchanged" is green on an implementation with no suspension at all, which still misfires on other transitions. Assert the signal the behaviour uniquely produces: attach a spy to **every** field's `change` event, drive several loads across record types, expect **zero** calls; then perform one real user tick and expect exactly **one** — the positive control that stops the zero from passing vacuously. Spy on the event, not on the handler's method name: string-resolved listeners may bind at registration time, so a spy installed later on the controller method sees nothing either way, and the zero would be meaningless.

## 8. No contract yet — write the consumer's expectations first, and ask for a route that doubles as a provisioning probe

When the consumer is planned before the producer's contract exists, neither wait nor guess silently.

- Emit a paste-ready **note to the producer's `/plan`**, the consumer side of
  [`SCHEMA_CONTRACT_HANDOFF.md`](SCHEMA_CONTRACT_HANDOFF.md).
- Gate the consumer's `/work` on a **contract table**: one row per claim the plan builds on (endpoint,
  envelope, read-back type, write format, absent-vs-`[]`, create path, degrade state). Each row gives
  the plan's default and the file to verify it in.

Field case: the producer adopted the note wholesale. Every row resolved to its default, and the one
flip, a display list the producer added, cost one model field. Earlier that morning a different draft
of the same contract had described an upstream-proxied tree endpoint with a server-computed `checked`
flag. It was superseded before any consumer code existed, and the table made that a non-event.

What to put in the note, beyond shapes:

- **A dedicated read route for the gated list, not the grid endpoint.** On an older producer the route
  404s, the reference load fails, the gate stays shut and the destructive key is never built, on create
  as well as update. The route *is* the provisioning probe, so deploy order stops mattering for that key.
  Reusing a generic list endpoint loses this: the endpoint exists on the old producer, so the gate opens
  and the key is sent. Safety then rests on the old writer ignoring an unknown key. Verify that
  separately, including any framework edge case where it does not.
- **No server-computed selection flag** (`checked`) on the list. The record's read-back is then the only
  source of the selection, so create needs no special case and the two sources can never disagree.
- **Types the client can read without guessing**, such as a JSON boolean rather than a raw `TINYINT`.
  Say the client coerces anyway, so the producer is not blocked on it.
- **Acceptance rows the client can physically produce** (§ 5), written into the note so they land in the
  producer's contract.

## 9. A partial-success envelope that also means "nothing saved" cannot be decided by the client

A producer that writes a parent row and then a nested list often answers "row saved, list not" with a
failure envelope on a 2xx status: `{success:false, msg}`, plus the new `id` on create. That creates two
consumer traps.

- **The generic failure handler has nothing to read.** A handler that branches on 4xx / 5xx shows a
  generic message for a 2xx failure, and the producer's text is swallowed. Handle the envelope before
  delegating.
- **Reload-vs-retry is decidable only when the body proves the row exists.**
  - On create, the returned `id` proves it. Close or reload; otherwise the user's retry creates a
    duplicate row.
  - On update, check whether the producer's generic exception path emits the *same* envelope when the
    row did **not** save. In the field case it did, so the edit stayed open (a retry is an idempotent
    PUT) and the list view reloaded either way.
  - Never decide by matching the message text. Ask the producer for a discriminator such as
    `"saved": true` in the note back to its owner.
  - Spec a 4xx sent **through the save path**, so the new branch cannot silently swallow every failure.

## Anti-patterns

- ❌ "Empty picker ⇒ send `[]`, the degraded tenant accepts it" — the harmless case is the only one you thought about.
- ❌ Deriving a write payload from a lookup / reference store instead of state seeded from the record.
- ❌ Reading the contract once at `/plan` and never again — the owner's corrections land in their working tree while you build.
- ❌ Leaving "reader root `result` vs `data`" as an open question when the producing controller is one grep away.
- ❌ Treating a contract's description of *your* framework as verified because the rest of the contract proved accurate — the shapes and the claims-about-you have different authors' confidence behind them.
- ❌ Copying an acceptance criterion whose signal your client cannot emit; a row that passes on a broken producer is a false negative you shipped on purpose.
- ❌ Correcting a contract's mistake only in your own plan. The sentence stays wrong for the next consumer until its owner fixes it.
- ❌ `!!row.flag` on a value the producer casts from a DB integer — the string `"0"` is true, and a flag re-sent on every save persists the misread.
- ❌ Proving "a load never fires the invariant handler" with one transition; only an event spy across several loads plus a positive control is set-order-independent.
- ❌ Skipping the gated key when the gate is closed, but leaving the value a failed save set on the record — the next save sends it anyway.
- ❌ Pointing a gated reference list at a generic list endpoint when a dedicated route would have made an older producer fail closed.
- ❌ Closing an edit on a 2xx failure envelope without proof the row exists — or keeping it open on create, where the retry duplicates the row.
