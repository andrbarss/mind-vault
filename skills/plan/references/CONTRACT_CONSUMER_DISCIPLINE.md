# Consuming a plan-stage contract — loaded-gated clearing keys, re-read at `/work` end, envelopes verified against the producing code, and the claims the contract makes about *your* codebase

Load when a plan builds **against** a contract another codebase emitted at *its* plan stage — the consumer side of [`SCHEMA_CONTRACT_HANDOFF.md`](SCHEMA_CONTRACT_HANDOFF.md): an admin-UI write-side coded ahead of the API, a client built from a sibling service's draft, any "shapes are authoritative as intent, re-verified at the owner's `/wrap`" arrangement. Five disciplines. The first three were field-caught on one idea (the first destroys data); §4 and §5 came from a later consumer of a contract whose §2 was an explicit *build spec* for the consuming repo — the richer the contract, the more of its prose is inference about code its author cannot run.

## 1. A `[]`-means-clear write key is a positive statement — gate it on the reference list having loaded

The contract shape that bites: key **absent** = nothing changes, `[]` = **clear every value**, non-empty = replace. The consumer draft derived the key from a *reference list* (the catalogue of things a value can attach to) that the form loads asynchronously after it opens, and reasoned about the one case where an empty list makes `[]` harmless — a degraded tenant with no rows at all. Two other cases produce the same empty list and are **indistinguishable on the client**: the list has not answered yet (the user edits an unrelated field and clicks Save on a slow tenant) and a transient load failure (timeout, 500, an auth race). Both serialise `[]` and wipe every value on the record. The architect pass caught it; every spec was green on the broken design, and the verification walk asserted the harmful behaviour as the expected one.

The rule: a key whose emptiness is destructive must never be computed from a list whose emptiness is ambiguous. Three parts, all needed:

1. **Derive the payload from state the component owns** — seeded from the record's own read-back and extended by the user's edits — never from the reference store. The reference list only says which ids are *active*; it is not the source of the values.
2. **A loaded-gate set only on a successful load** (`success !== false` on the load event, never "the store is non-empty"). While the gate is closed the editor is read-only and any "add" affordance is disabled — the user must not be able to edit what cannot be saved.
3. **An absent branch.** The payload builder returns `undefined` while the gate is closed and the host sets the key **only for an array**. Not loaded serialises as *absent* (= untouched), never as `[]`. `[]` is emitted only when the list loaded successfully and there is genuinely nothing to send.

Spec the three empties separately, because one green row hides the other two: loaded-with-zero-rows → `[]`; load answered `success:false` → `undefined` and the host's writer payload has **no** key; load never answered → `undefined`, then present once it resolves. Add one runtime row that throttles the reference request and Saves immediately — the body must carry no key and the values must survive a reopen.

The tell in a draft plan or spec: any row that asserts `[]` as the *expected* output of an empty list. Treat it as a finding, not a test.

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


## Anti-patterns

- ❌ "Empty picker ⇒ send `[]`, the degraded tenant accepts it" — the harmless case is the only one you thought about.
- ❌ Deriving a write payload from a lookup / reference store instead of state seeded from the record.
- ❌ Reading the contract once at `/plan` and never again — the owner's corrections land in their working tree while you build.
- ❌ Leaving "reader root `result` vs `data`" as an open question when the producing controller is one grep away.
- ❌ Treating a contract's description of *your* framework as verified because the rest of the contract proved accurate — the shapes and the claims-about-you have different authors' confidence behind them.
- ❌ Copying an acceptance criterion whose signal your client cannot emit; a row that passes on a broken producer is a false negative you shipped on purpose.
- ❌ Correcting a contract's mistake only in your own plan. The sentence stays wrong for the next consumer until its owner fixes it.
