# A local flag pushed into an external record: a default is not an answer, one field needs one source

Load when a plan starts sending a value the application already stores (a consent / opt-in flag, a
preference, a status) to an external system that keeps **its own** copy on a longer-lived record: a
PMS or CRM client, a mailing-list contact, a payment-provider customer. The local column was only
ever read locally. Once it is sent, every weakness in how it was written becomes a write into
someone else's record, and that record outlives the booking or order that wrote it. Three traps,
each found in the field by a review lens after the engine had passed the diff.

## 1. A `NOT NULL DEFAULT 0` column cannot say "never asked"

A boolean column with a default stores the same `0` for "the user said no" and "this path never
asked". While the value is only read locally, the ambiguity is harmless. Once it is sent, a
`0` from a path that never asked **clears a real answer** on the external record. That happens
wherever the external system resolves several local rows to one record, for example a client matched
by e-mail.

- **Presence of the input is the signal.** Pass the value to the sending code only when the request
  carried it: a parameter read with no default, so absent stays `null`. Store the column default as
  before, and send **nothing**. Normalise a present value (the string `'1'` → 1, anything else,
  non-scalars included, → 0) once, into one variable, and use that variable both to store and to
  send. The two cannot differ.
- **Name every writer of the column and classify it:** answers, defaults, or copies. Only writers
  that answer may cause a send. The creation paths that never ask (partner APIs, channel imports,
  admin creates) must send nothing, even though they reach the same outbound call.
- **Rows imported *from* the external system send nothing.** Their local value is a default. The
  external record already holds the truth, and pushing the default back overwrites it. An
  `imported_from_*` marker is often already there; use it.
- **An update call re-sends the column wholesale.** If the external "update" call carries the value
  on every update, the ambiguity is not "eventually" but "immediately": several creation paths issue
  an update right after create. When a nullable column (`NULL` = never asked) is out of scope, record
  the residual as a condition on the consumer ("honour the value on update only once the producer can
  tell a default from an answer") rather than a footnote.
- **One wire rule, in one pure function.** A clean `0`/`1` is sent. `NULL`, `''` and legacy junk
  (`'2'`, `'on'`, left by an earlier raw write) send nothing. The transport appends the key only when
  that function returns non-null, so an unchanged call is byte-identical to before (pin that).

## 2. One external field fed from two local copies flips back and forth

The same person's answer often lives in two tables: once on the order or booking (captured at
checkout), and once on a person or guest row (captured later, at check-in or in a profile). If call A
sends the booking's copy and call B the person's, the external field takes whichever call ran last.
A withdrawal given later is **undone** by the next routine update of the other record. This is a
compliance failure, not a cosmetic one.

- **Pick "the latest answer wins" and make the tables agree.** Copy the answer at the one sink every
  writer of the later-captured table goes through, the model's `save()`, not each controller. Copy
  only a clean value, only from the row that represents the person (the *main* guest, the account
  holder), and only when the saved data carried the key, so unrelated saves cost no query.
- **Close the reverse direction too.** A later edit of the booking copy (an admin form) must write the
  person row as well. Otherwise the two diverge again and the next person-row call re-sends the old
  answer.
- **Widen to the same person's sibling records.** A cart or order with several bookings for one
  person means several local rows, one external record. Copy the answer to the siblings that are
  plainly the same person (same parent + same contact e-mail), not to the whole parent: a group
  booking's other rooms may be other people with their own answers.
- **Execute the copy, don't pin it.** Bypass the constructor, give the model a recording fake adapter,
  and assert the exact `UPDATE` (including the sibling `WHERE`). A source pin would certify text, not
  which rows move.

## 3. A lossy local writer becomes an external write

Legacy writers of the column were written when a wrong value only affected a local report: a form
that stores `param == 'on' ? 1 : 0`, a raw `_getParam()` stored unnormalised into a `TINYINT`. Before
sending, check each writer against its real client: does the form actually submit the field (bound
checkbox, not disabled), and with which value (`inputValue`, `uncheckedValue`)? A disabled field is
never submitted, so that path never writes. A field that is absent from the form stores 0 on every
save, and would now clear the external record on every edit. The client usually lives in another
repository; read it there before calling the risk real or cleared.

## Checklist for the plan

1. List every writer of the column: answers / defaults / copies. Only answers cause a send.
2. List every outbound call that carries the value, and which local copy each reads.
3. Same person in two tables? One sink, latest answer wins, both directions, same-person siblings.
4. Rows imported from the external system: skip.
5. One pure wire rule; the key is absent unless the value is clean; unchanged calls pinned
   byte-identical (generate the expected literal by running the **pre-change** code, not by hand).
6. The residual default-vs-answer risk goes into the consumer's contract as a condition, and a
   nullable-column follow-up is filed.
