# Consuming a plan-stage contract — loaded-gated clearing keys, re-read at `/work` end, envelopes verified against the producing code

Load when a plan builds **against** a contract another codebase emitted at *its* plan stage — the consumer side of [`SCHEMA_CONTRACT_HANDOFF.md`](SCHEMA_CONTRACT_HANDOFF.md): an admin-UI write-side coded ahead of the API, a client built from a sibling service's draft, any "shapes are authoritative as intent, re-verified at the owner's `/wrap`" arrangement. Three disciplines, each field-caught once on the same idea; the first is the one that destroys data.

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

## Anti-patterns

- ❌ "Empty picker ⇒ send `[]`, the degraded tenant accepts it" — the harmless case is the only one you thought about.
- ❌ Deriving a write payload from a lookup / reference store instead of state seeded from the record.
- ❌ Reading the contract once at `/plan` and never again — the owner's corrections land in their working tree while you build.
- ❌ Leaving "reader root `result` vs `data`" as an open question when the producing controller is one grep away.
