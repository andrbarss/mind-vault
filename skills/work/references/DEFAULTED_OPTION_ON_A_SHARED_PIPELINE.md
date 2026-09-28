# A defaulted option on a shared pipeline — and the write gate that hides the caller who forgot it

Load when a bug report says a computed value (a price, a total, a permission set) is **right when the
record is created and wrong after a recalculation**, or that it breaks **"only when feature X is on"**
although X has nothing to do with the value.

## The shape

A shared calculation takes an options array. One option has a default chosen for the *display* caller
(a calendar, a list, a preview), where a rule that depends on the whole input cannot be shown and is
left out:

```php
$forDisplay = isset($input['for_display']) ? $input['for_display'] : true;   // backward compatible
if ($forDisplay && $rule['depends_on_whole_stay']) { continue; }
```

Every caller that computes a value **to store** must pass `false`. The creating path does. A
recalculating path written later passes it only under a condition, or not at all, and silently gets the
display result: the rule is left out, no error, a plausible number.

## Why it shows only with feature X

The recalculating writer stores its result only when something changed:

```php
if ($result['change'] != 0 || $result['base_change'] != 0) { $row->update(...); }
```

Computed without the rule, the result equals the base value. Without X both deltas are 0, the gate
stays closed and the value stored at creation survives. The defect is there and invisible. X (a
surcharge, a rate rule, a second adjustment) makes one delta non-zero for its own reasons. The gate
opens and the wrong result overwrites the right one.

So X does not interact with the lost rule. It only opens the gate. Read "only with X" as
**"X makes the wrong result storable"** and look upstream of the gate for a missing input.

| Recalculated without the rule | Deltas | Gate | Stored value |
| --- | --- | --- | --- |
| X off | 0 and 0 | closed | the correct one from creation |
| X on | one is non-zero | open | the wrong one |

## How to find it

1. **Log the option at the calculation, not the result at the caller.** One line per call with the
   option's effective value shows the creating call and the recalculating call disagreeing.
2. **List every caller of the calculation** and write one row per caller: passes the option, passes it
   conditionally, omits it. A grep for the option's **name** finds only the callers that pass it; the
   ones that matter omit it. Grep for the **function**.
3. **Sort the omitting callers** into display (the default is right) and storing or quoting (the
   default is wrong).
4. **Walk the "X off" case through every other branch of the writer.** A recalculation that resets the
   value when the totals differ, or a second rule on another row of the input, opens the gate without X.

## How to fix it

- Set the option **unconditionally** in every storing caller, next to the call, with a comment that says
  why this caller is not a display.
- Fix **all** storing callers in one change. The first fix here covered the reported path; an
  independent review found a second one behind a different action (remove a code, cancel a sibling
  record) that the automated review had passed as clean, because it verified the fix it was shown.
- Record the quoting callers you leave on the default (a price shown before the record exists) as a
  known difference, with the reason.
- Do not flip the default. The display callers rely on it and they are the ones that do not name it.

## How to test it

- Execute the calculation on **both** inputs, with X and without X, with the option set: the rule
  applies in both.
- Execute it on both inputs with the option **unset** and assert the deltas: 0 and 0 without X,
  non-zero with X. This pins the reason the defect hid and fails if the gate's inputs change.
- Pin, per storing caller, that the option is assigned at the top level of the method immediately
  before the call. Say in the test which assertions fail when the fix is reverted: the executed ones
  set the option themselves and pass either way.

## What changes when the fix ships

The gate now opens where it used to stay closed. For records carrying such a rule the recalculation
writes the row, rewrites its detail rows and fires whatever the writer fires, on every call, as it
already does for an ordinary rule. Any dry-run or quote built on the same calculation starts including
the rule. Name both in the change description.

## Related

- [`AUDIT_NEWLY_REACHABLE_CODE.md`](AUDIT_NEWLY_REACHABLE_CODE.md) — the fix opens a write path that
  was closed for these records.
- [`EXECUTE_OVER_PIN.md`](EXECUTE_OVER_PIN.md) — executing a calculation the suite cannot construct.
- [`../../plan/references/PRODUCER_ARGUMENT_CONTRACTS.md`](../../plan/references/PRODUCER_ARGUMENT_CONTRACTS.md)
  — what a producer does with an absent argument.
- `rules/RULE_self-sweep-before-push.md` trigger 6 — siblings converging on one sink.
