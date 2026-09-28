# Placeholder rows in a listing — a client posts back what it was shown

Load when a plan touches a listing that **pads its result with rows that do not exist yet** (one entry
per booked person, per seat, per slot), or a writer that creates those rows from what the client sends.

## The shape

The listing returns one entry per expected row. Stored rows come from the table. The rest are built in
code with defaults:

```php
for ($i = 0; $i < $expected; $i++) {
    if (!isset($rows[$i])) {
        $rows[$i] = ['position' => ++$last, 'consent' => null, 'is_first' => (int)($i == 0), ...];
    }
}
```

A client renders every entry as a form and posts the form back. For a placeholder that post is a
**create**. Every default in the placeholder is therefore a value the client may send as the user's
answer.

## What goes wrong

| Placeholder default | Client renders | Client posts | Effect |
| --- | --- | --- | --- |
| `consent: null` | an unticked box | `0` | a consent given earlier, stored on the parent, is withdrawn |
| `is_first: 1` on entry 0 | the fields of a first row | the row | the writer must set the flag itself; the client cannot |
| `position: last + 1` | that number | that number | the numbers depend on which row was saved first |

The first row is the dangerous one when a writer later **copies the row's value to the parent** or
sends it to an external system. The listing turned "not asked here yet" into an answer.

## Rules for the plan

1. **A placeholder field that has a source shows the source.** If the parent holds the value (the
   consent given at booking, the contact's name), the placeholder carries it. `null` is for fields that
   have no source.
2. **Apply the sender's rule for "is this an answer".** If the code that sends the value outward
   ignores some stored values (a column default on an imported parent, a value outside the allowed
   set), the placeholder ignores the same ones. Call the same function. Do not write a second rule.
3. **Read the column definition before writing the description.** For a `NOT NULL DEFAULT 0` column
   "never asked" is stored as 0, so "null when there is no answer" is false. Say what the consumer
   gets: "0 also when the question was never asked".
4. **The writer decides the flags, the listing only predicts them.** The listing marks entry 0 as the
   first row. The writer sets the flag when the table has no rows. The two agree only if the client
   saves entry 0 first. Decide what happens otherwise and write it down: refuse, renumber, or accept
   and flag that row.
5. **One query for the parent.** The placeholder's source is the parent row the listing has already
   loaded for the expected count. Read it once, outside the loop.

## Tests

- Execute the listing on fixtures: no rows, one stored row and one placeholder, a stored first row
  whose value differs from the parent's (the stored value wins).
- **Fixtures use shapes the producer returns.** Check what the parent reader returns on a miss and for
  a column that cannot be null. A fixture of `false` or `null` that the reader never produces tests a
  branch that does not exist. Field case: the reader answered a miss with a non-empty array, so the
  `empty()` guard in the new code was dead, and the `null` fixture stood for a column that is
  `NOT NULL`.
- Non-first placeholders keep their key set. Assert the absent keys.

## Documentation

- The schema's description of the field states the placeholder case in API terms.
- Captures taken before the change show the old default. Name them in the backref so that a reader
  comparing a capture with the schema knows which one is current.
