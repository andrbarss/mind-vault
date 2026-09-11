# Mutation pass — prove each guard can fail, without shipping a mutation or trusting a void run

Load when a plan's verification step says "remove X → test goes red", when a review asks whether
the new tests can actually fail, or after a fix cycle adds guards. A mutation pass is the cheapest
way to find a test that passes for the wrong reason — and, run carelessly, a way to commit a
disarmed guard behind a green suite.

## Plan the mutations from the guards — one per guard

- List every guard the change introduced: each refusal, each degrade gate, each retry or
  translation branch, each coercion, each fixture safety step. One mutation is the **smallest edit
  that disables that guard**. Write down the test you expect to go red.
- **Planning them exposes weak assertions before anything runs.** Field case: fifteen save tests
  asserted only HTTP 200, but the API reports a post-save failure as `200 {success:false}` — so a
  mutation making the writer fail *after* the save would have stayed green. The fix was a helper
  asserting `success: true`, not another mutation.
- **Check that each data-provider row can discriminate.** Under coercive typing, `"12.0"`, `"+12"`,
  `" 12"` and `"12e0"` all become integer 12. A hostile-id row that only passes because id 12 is not
  in the database proves nothing; build the row from the fixture's own id and assert the observable
  (the item is still listed). Rows no coercion can map onto the fixture pin behaviour only — say so
  in the test's docblock.
- A fix cycle adds one mutation per fix, each expected to fail exactly its own regression test.

## Run against committed code, one mutation at a time, restoring from git

- **Commit first.** Each mutation: apply by exact-anchor replace (abort loudly if the anchor is
  missing or not unique) → run the one relevant suite → restore the file in a `finally`. At the end,
  `git diff --stat` over the mutated paths must be empty, or identical to the known uncommitted edits.
- **Run the unmutated baseline in the same script first.** It is the only way to tell a real red from
  a broken harness.
- **Never put the mutation script in the same parallel tool batch as `git add` / `git commit`.**
  Parallel tool calls give no ordering guarantee: a staging call that lands mid-mutation commits a
  disarmed guard, and every signal afterwards reads healthy. Treat the pass like database-exclusive
  work — nothing that stages, and no other suite on the same shared database, runs beside it. If it
  happened anyway, check HEAD for every guarded statement before trusting the commit.

## Read the result, not the colour

- Record, per mutation, the summary line and the names of the tests that went red. A mutation that
  turns nothing red is a **missing test**, not a pass.
- **The same fatal on every mutation is a void run.** Field case: a regex-driven edit that inserted
  an `assertSaved()` helper also matched the helper's own body and turned it into a self-call; every
  mutation "failed" on memory exhaustion. The unmutated baseline would have shown the fatal first.
- **A mutation that reproduces the defect it guards can leave debris.** Field case: removing a test
  sweep's coverage of a parked table did exactly what the fix prevents — the test's own cleanup
  deleted the marker parents and stranded a child row no later sweep could match. Check for leaks
  after the pass, and clean with a delete constrained by the defect's own signature (for example,
  rows whose parent and target are *both* missing), never a blanket truncate of shared data.

## Anti-patterns

- ❌ Mutating uncommitted code, then restoring by hand.
- ❌ Running the mutation script beside a staging command or another suite on the same database.
- ❌ Counting a mutation as killed when every run died on the same error.
- ❌ Adding a mutation for a guard whose test asserts a status code the failure path shares.
- ❌ Hostile-input rows whose outcome depends on which ids the shared database happens to hold.

## Related

- [`EXECUTE_OVER_PIN.md`](EXECUTE_OVER_PIN.md) — a pin proves text; a mutation proves the test behind it can fail.
- [`../../../rules/RULE_self-sweep-before-push.md`](../../../rules/RULE_self-sweep-before-push.md) — trigger 4 (read the count, not the colour) and trigger 7 (staged-set verification).
