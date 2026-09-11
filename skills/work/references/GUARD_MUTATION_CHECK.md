# Guard mutation check — prove each spec row is load-bearing before push

Load at the end of a `/work` step that added **guards** and the specs that claim to pin them. A guard
here means a load gate, a truth table, a self-exclusion, a lifecycle config or a failure branch.

A green suite proves the rows pass on the code you wrote. It does not prove that any of them would fail
if a guard were gone. Some rows stay green either way:

- a row written against a stub that always answers success;
- a row that only asserts the default value;
- a row whose setup never reaches the branch it names.

All of them pass, and none of them protects anything. The mutation check is the cheap way to find them
before a reviewer does.

## The recipe

Once the suite is green and committed:

1. **List the guards** the step added, one line each, naming the file and the exact expression. For
   example: "the payload is `undefined` while `pickerLoaded` is false", "`selfId` is null for a
   phantom", "a failed load resets the gate".
2. **Write one substitution per guard** that removes or inverts it. Use the smallest edit that makes
   the guard wrong while the code still parses. Examples: `if (isString(x))` becomes `if (true)`;
   `=== false || === 0 || === '0'` becomes `=== false`; the reset line is dropped.
3. **Run them one at a time**, never batched. For each: back the file up, apply the substitution,
   check that it applied, run the suite and record the failing specs, restore the backup.
4. **Read the results.** Every mutation must fail at least one spec, and the failing spec's title
   should name the guard. A mutation that stays green means a vacuous row or an untested guard. Fix
   the row (usually its stub or its setup), re-run that one mutation, and only then push.

```bash
run() {   # run <name> <file> <perl-expression>
    cp "$2" "$2.mutbak"
    perl -0pi -e "$3" "$2"
    if cmp -s "$2" "$2.mutbak"; then
        echo "== $1: DID NOT APPLY"; mv "$2.mutbak" "$2"; return
    fi
    echo "== $1"
    <suite command that prints the totals and the failing spec names>
    mv "$2.mutbak" "$2"
}
run "closed gate still sends the key" src/controller.js 's/if \(isString\(payload\)\) \{/if (true) {/'
```

Notes on the script:

- `-0` lets a substitution span lines.
- `\x27` stands for a single quote inside a single-quoted perl expression.
- `cmp` catches a pattern that silently matched nothing. A mutation that never applied would
  otherwise read as green, which is this check's own vacuous pass.

## Rules that keep it honest

- **Back up and restore with `cp` / `mv`, not a version-control checkout.** The restore must work on
  new, untracked files, and must not touch anything else in the tree.
- **Run it alone.** While the script runs, never commit, and never let a reviewer or a second agent
  read the working tree: a staging command or a review can pick up a mutated file. Point a concurrent
  reviewer at committed objects (`git show HEAD:<path>`, `git diff <base>...HEAD`). After the run,
  confirm the tree matches the committed state before the next commit.
- **One guard per mutation.** A mutation that breaks two guards at once cannot tell you which row
  guards which.
- **Mutate only after the suite is green and committed.** Otherwise real failures and mutation
  failures mix in the output.
- **Re-run for guards added later.** A review round that adds guards gets its own round of mutations.
  Record both rounds in the plan's execution log, as mutation and number of failing specs.

## Field calibration

The field case was a client-side load gate on a tree picker, checked against an in-browser suite:

- **First pass:** 10 mutations, covering the store lifecycle, the gate, self-exclusion, the truth
  table and the failure branch.
- **Second pass:** 4 more mutations after the pre-push review added guards: restoring a stale value, a
  4xx reaching the generic handler, a list reload on a partial failure, and a buffered listener.
- **Result:** all 14 failed at least one spec, between 1 and 6 each, and the whole run took a few
  minutes.

The check could reach those guards only because the rows used a URL-aware request stub. The first
draft's stub answered every URL with success, and could never have reached a closed gate.

## Related

- [`EXECUTE_OVER_PIN.md`](EXECUTE_OVER_PIN.md) — the sibling question for methods a suite cannot construct: does any test *call* it?
- [`../../plan/references/VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md`](../../plan/references/VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md) — a guard whose discriminating value the environment flattens asserts nothing.
- `RULE_self-sweep-before-push` trigger 4 — read the count, not the colour.
