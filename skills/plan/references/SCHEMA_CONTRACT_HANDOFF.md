# Plan-stage schema contract — the DDL hand-off that unblocks a parallel consumer

Load when a plan's schema change will be consumed by work in **another codebase or by another team / agent swarm** — an admin-UI write-side, a sibling service, a client generator — that would otherwise sit blocked until `/work` ships, or worse, build against a guessed schema. Field-proven twice: once to freeze a deferred write-side's writer invariants so a later CRUD IDEA could be planned against them, and once to hand a display-slot column set to a parallel UI team the same day the plan locked.

## The pattern

`/plan` emits a standalone **`schema-contract.md`** into the idea's archive dir *alongside the plan, before `/work` starts*. The plan lists it as a plan-time deliverable; the implementing migration later **mirrors it verbatim** (divergence between contract and migration is a review finding, not a judgement call).

The contract carries five sections:

1. **The model** — a compact semantic table: column → meaning → who writes it → who reads it. One paragraph of narrative on what a row *is* under the new shape.
2. **UP DDL and DOWN DDL, exact** — copy-paste SQL, not prose. State the backward-compatibility rule the DDL encodes (e.g. which `DEFAULT` makes every pre-existing row keep its current behaviour with zero backfill) and what the DOWN destroys (curation data, orphaned semantics) so the rollback cost is agreed in advance.
3. **Writer invariants the DB cannot enforce** — numbered, one per line. Two disciplines here:
   - **Composability check**: read every pair of invariants as a naive consumer would. Two individually-true rules can read as contradictory ("full delete+reinsert is legal" vs "never delete a row to remove one membership") — when they can, add an explicit composition sentence ("X is legal **iff** Y") rather than trusting the reader to reconcile them. Field-caught by an architect pass: the contract locks at plan time, so a wording ambiguity ships to the consuming team and surfaces as a wrong write-side months later.
   - **Reader-tolerance declarations**: state what readers IGNORE ("a slot's position is ignored while its flag is 0"), because that is what makes a lazy writer harmless and tells the consumer which cleanup writes it may skip.
4. **What the reading side will expose** — the response fields the consumer's data will surface, so the writer team sees the round trip, not just the tables.
5. **A seed / probe example with expected output arithmetic** — concrete INSERTs plus the exact derived result ("rows so-configured ⇒ list A = [1,2], list B = [3,1], list C = [2]"). This one section does triple duty: the architect pass can verify the arithmetic against the model, the implementing side's live verification curls it as its acceptance check, and the consuming side can seed the same rows and assert its UI. If the two codebases ever disagree, the seed example is the arbitration record.

## Why plan-time, not work-time

- The consumer starts immediately — schema debates (naming, discriminator-vs-flag shape, per-list ordering) happen once, in the plan's architect review, instead of after two codebases built against different guesses.
- The contract is small enough to review exhaustively at plan time; the migration that mirrors it later needs only a "matches the contract verbatim" check.
- Locking the DDL early is safe *because* the contract is additive-biased: when the design demands additive columns with behaviour-preserving defaults (see the architect PASS 4 additive-columns bullet for the read-path consequences), a later plan revision is a new contract version, not a silent drift.

## Anti-patterns

- ❌ Handing the consumer the plan document itself — plans carry execution sequences, open questions and repo-relative paths that mean nothing in the other codebase; the contract is the extracted, stable subset.
- ❌ A contract without the DOWN DDL — the consumer needs to know what a rollback window does to their writes.
- ❌ A seed example without expected output — un-checkable, so it decays into decoration.
- ❌ Writing the migration first and extracting the contract after — the review order inverts, and the consumer's blocked window extends through /work.
