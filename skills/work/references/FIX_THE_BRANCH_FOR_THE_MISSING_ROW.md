# A failure "only while the record is in state S" — fix the branch that handles the missing row

Load when a bug report ties a refusal or a wrong value to a **state** of the parent record ("only when
the order is not paid", "only before the account is verified"), and the proposed fix is to **create a
child row earlier** so that it always exists.

## The shape

A child row (the first member, the owner, the default address) is created by a step that runs late in
the parent's life: on payment, on confirmation, on import. Until that step has run, the writer that
saves a child takes its **empty-list branch**. That branch is rarely exercised, and it holds the defect:

```php
$saved = $manager->getRows();
if (empty($saved)) {
    $saved['is_first'] = 1;          // meant: $data['is_first'] = 1
}
...
if (!isset($id) && count($saved) == $limit) {   // an empty list now counts 1
    return $this->refuse('limit reached');
}
```

One wrong variable, two effects:

| Parent booked for | Empty list counts | Result |
| --- | --- | --- |
| 1 | 1 == 1 | the first and only child is refused, "limit is 1" |
| 2 or more | 1 != n | accepted, stored **without** the flag |

The refusal is loud and reported. The missing flag is silent: every consumer of the flag treats the row
as an ordinary one, and the late step, finding no flagged row, inserts a second one.

## Why "create the row earlier" is the wrong fix

The state in the report is a correlation. The cause is "no child row yet", and the late step is only
the usual reason a row exists. Guaranteeing the row:

- leaves the defect in place for every parent that reaches the writer without a row;
- needs an insert on **every** path that creates a parent (storefront, admin, imports, queue workers);
- leaves child rows, often with personal data, on parents that expire or are cancelled in state S.

Before accepting such a fix, list where the late step does **not** run. Read its guards:

```text
late step runs only if:  feature enabled  AND  parent type supports it  AND  not a reopened parent
```

Each false guard is a parent that is past state S and still has no row. If the list is not empty, the
report's state is not the condition, and the precondition cannot be guaranteed from one place.

## How to find the defect

1. Grep the message. Read the condition that emits it and every variable in it back to its assignment.
2. **Look for a write to the collection that is about to be counted or iterated.** A key set on the
   list that was just read is the tell: the list is input, the payload is output.
3. Line the sibling writers up. The same "first one gets the flag" block usually exists in an admin
   action and a queue consumer. The odd one out is the defect, and the siblings show the intended line.
4. **Grep the backlog and the archive for the message and the symbol before analysing further.** A
   defect of this kind is often already recorded: as a finding in a documentation or verification pass,
   or as an idea filed from a review. Use that number and its notes. Do not file a second one.

## How to fix it

- Set the flag on the payload, after any allow-list filter that would drop it.
- Move the limit check to **one** function and call it from every writer that has a limit. Compare with
  `>=`: a parent that already holds more rows than its limit must refuse too, and `==` lets it through.
- Do not repair existing rows in the same change unless the plan decides it. Count them first.

## Tests

- Execute the limit function on a table: empty list, at the limit, over the limit, limit 0, the limit as
  a numeric string.
- Pin the writer's source: the flag is set on the payload; nothing writes to the list; the assignment
  sits **after** the allow-list filter; the flag's name is **not** in the allow-list, so a request
  cannot choose it.

## What changes when the fix ships

State it in the PR and the archive. Reviewers and consumers will meet each of these:

- the first child saved through this writer now carries the flag, so the rules for a flagged row apply
  to it (mandatory fields, when it is sent to an external system, what is copied to the parent);
- the late step finds a flagged row and no longer inserts its own;
- a parent over its limit, or with a limit of 0, refuses where it used to accept;
- which row gets the flag when the first save does not name the first position. Decide it, or record it
  as an open owner decision.

## Documentation that the fix makes false

A sentence that was true of the rare case can be false of the normal one. When the change turns the
flagged row from an exception into the default for this writer, re-read every sentence of the endpoint's
description that speaks of "a row" in general, not only the sentence being added. Field case: "a
complete row is handed to the external system" had always been false for the flagged row; the fix made
the flagged row the first thing a client saves.
