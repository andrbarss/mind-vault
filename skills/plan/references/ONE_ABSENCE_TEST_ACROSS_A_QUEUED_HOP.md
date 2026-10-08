# One "absent" test across a queued hop: the worker must not re-decide what the action accepted

Load when a plan touches an **optional field** that crosses a queue: an API action validates it and
writes a task row, and a worker later turns that row into the real record. This is the case where the
action enqueues the **raw request** (a JSON body), not only the validated columns, and the worker reads
its copy of the value from the raw request.

## 1. The defect class

The action and the worker each decide on their own whether the field "is there", with different tests.
Every input on which the two tests disagree skips the action's validation and lands in the worker's
converter.

Field case (a downstream PHP booking API, a birthday field):

| Input | Action (`isset && !empty`) | Column | Worker (`isset`) on the raw body | Effect |
| --- | --- | --- | --- | --- |
| absent | no birthday | `NULL` | absent | none |
| `''` | no birthday | `NULL` | **present**: `date_create('')` | the booking date stored as the guest's birthday |
| `'0'` | no birthday | `NULL` | **present**: `date_create('0')` = `false` | `TypeError` in a `?DateTime` parameter: the task never becomes a record |
| `'1990-05-17'` | validated | the date | present | correct |

Nothing failed in review: the action's validation looked complete, and the worker's line was "only a read".
Converters with forgiving defaults make it worse:
- `date_create('')` is *now*;
- `(int)'abc'` is `0`;
- an empty-ish value that one side calls absent becomes a real value on the other.

## 2. The rule

- **Either the worker uses the action's absence test, verbatim**, the same predicate on the same raw key;
- **or the queue carries the normalised value** and the worker reads that copy, never the raw request.

Prefer the second when the action already writes a validated column. The raw body is still useful as an
audit trail, but the worker should not re-parse it.

## 3. Prove it with a truth table, then with the real worker

- **Enumerate the input classes** for the field: absent, `''`, `'0'` / `0`, whitespace, a near-miss format,
  an array (`field[]=x`), and a valid value. Give each class a row and a column per hop: does the action
  accept it, the stored column, what the worker reads, the effect. Every accepted row must produce the same
  effect on both paths.
- **Run the real worker** on one task per accepted class, and read the effect from the record it writes.
  Re-implementing the worker's condition in a scratch script proves the language's semantics, not the
  worker (phantom verification). When the walk environment makes the worker crash *after* its write (a
  missing extension), read the write first; on a non-transactional engine it survives.

## 4. Tasks already stranded by the old mismatch

A converter error can be an `Error` (`TypeError`) rather than an `Exception`. A worker that catches only
`Exception` then skips its own failure path:
- no `failed()`;
- no try counter;
- the task is left "processing" and is retried for ever.

After the fix those tasks *succeed*, possibly long after their dates. Before deploy, give the operator a
fingerprint query per tenant for tasks whose raw body carries the formerly-mismatched values and that are
still unprocessed, so a human decides on each (for example, cancel the past ones).

## Related

- [`HOST_LOCAL_VALUE_IN_A_QUEUED_ROW.md`](HOST_LOCAL_VALUE_IN_A_QUEUED_ROW.md): nothing new ahead of a
  narrow `catch (Exception)` that can throw an `Error`.
- [`AMEND_A_QUEUED_TASK_PAYLOAD.md`](AMEND_A_QUEUED_TASK_PAYLOAD.md): writing into a payload that is
  already queued.
- [`EMPTY_IS_A_THIRD_STATE.md`](EMPTY_IS_A_THIRD_STATE.md): when empty means something other than absent.
