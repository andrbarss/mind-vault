# A preview of a record that does not exist yet — run the creator's code, draw with the reader's

Load when a plan adds a **preview**, **dry run**, **quote** or **draft document** of something an
existing endpoint creates: "show the customer the voucher / invoice / label / confirmation before it
is created", fed by the data the client is about to send to the creator.

## The shape

Today the document is drawn from a **stored** record: a reader finds the row and hands it to a
template. The preview has no row. The tempting design reads the request, fills the template's
variables and renders. It is wrong in three places at once, because what is stored is **not what was
sent**:

| Layer | What it does to the request | A preview that skips it shows |
| --- | --- | --- |
| The creator's preparation | looks up the catalogue item, takes name / price / validity / template / background from it, applies tenant settings, refuses what cannot be sold | the client's own price and texts |
| The model's save | maps the prepared entry to a row: derived dates, a price rule, defaults | other dates, another price arm |
| The database | coerces: decimals, integer ranges, date forms, text cut at the column length, a character set that cannot hold a character | `50` where the record says `50.00`, a text the insert would have cut or refused |

So the preview is four pieces, each **shared** with the path that exists:

1. **The creator's preparation, moved — not copied — into a builder** the creator and the preview
   both call. The creator saves what the builder answers; the preview draws it.
2. **The entry → row mapping, extracted from the save** into a method that reads and never writes.
3. **A read-back coercion**: a pure function from the row as built to the row as the database would
   hand it back, driven by a dated snapshot of the table's column definitions.
4. **The reader's renderer** — list entry, template choice, drawing — extracted from the action that
   serves stored records and fed an unsaved record hydrated from 3.

Equality of preview and record is then a property of the construction, and what remains to verify is
small enough to verify completely (below).

## Decisions to take with the owner before drafting

- **Access.** A stored document is usually addressed by a secret of the record (a code in a link). A
  preview has none, and every call costs a render. Decide the gate first; "the same gate as the
  creator, fetched server-side" is the usual answer, and it settles who pays for the load.
- **The contract is what changes the document or the answer.** A creator accepts buyer data, cart
  ids, flags for later steps. List per parameter whether **any** template can draw what it feeds —
  grep every template set, not the default one. Parameters that feed nothing are left out of the
  contract and dropped before the builder; implement that as a **list of what reaches the builder**,
  not a list of what is removed, so that a parameter nobody thought of is dropped by construction.
  Personal data in a query string is a second reason to leave it out.
- **What stands in for values that exist only later** (codes, PINs, a QR image). Take what the reader
  already shows for a record that is not paid yet; do not invent placeholders.
- **What an edit preview would be.** An "update" endpoint named in the request may be an example of
  the parameter set, not a fourth source. Ask.

## Traps in the extraction

- **Moved, not rewritten** holds only if the builder takes no mode flag. What the preview needs and
  the creator does not (an id that names nothing must be a refusal, not a failure) goes in a
  precondition the preview calls **before** the builder. The builder stays the creator's code.
- **A refusal has a shape.** Sibling creators may answer one refusal as a string and the rest as a
  list. The builder hands the value over as the creator emitted it; the preview normalises. Carry an
  explicit `refused` flag — an empty text is still a refusal.
- **A helper that imitates the framework is tested against the framework.** The builder reads an
  array where the action read the request object. Written from memory of another version of the
  framework, the helper replaced an empty string with the default; the installed one replaces only
  null. Execute the helper and the framework's accessor over the same rows, including a collision of
  route, query and form values.
- **The extraction boundary of the save.** Fields that belong to the insert (codes, author, creation
  time) stay in the save; an update branch nobody calls stays byte-identical; an object the mapping
  created and the save reused afterwards is rebuilt the same way. Count the save's callers — a
  fourth one in a service class is easy to miss.
- **The record's type may be derived from what only a stored record has** — a link row looked up by
  id. An unsaved record then reads as another type, and the renderer picks another template. Seed
  the unsaved record with what the lookup would have found rather than editing the shared type
  check; keep a nullable discriminator null (a `0` can read as "set").
- **A getter may compute.** "What is left of the amount" answers `stored − used` for a record with
  an id and the stored text for one without: a number in one case, a decimal text in the other, and
  the template prints both verbatim. Coercion to the database's text is necessary and **not
  sufficient** — only the comparison with a created record finds this.
- **Texts built from request input** reach whatever the application does with a text it sees for the
  first time (a translation registry that records unknown texts, with the request URL). Records are
  bounded by sales; previews by nothing. Switch that registration off for the preview's duration and
  restore it in `finally`.
- **The renderer's buffers and headers.** A template that throws half-way leaves document bytes in
  front of the error body; a template that sends its own headers leaves the length and type of one
  format on the answer in another. Record the buffer level on entry, close down to it, remove the
  headers a template may have sent.

## Verification that is proportionate

- **Creators unchanged:** the same request to the default branch and to the branch, answers and
  stored rows compared (`skills/work/references/LIVE_BEFORE_ORACLE.md`).
- **Reader unchanged:** the stored records' documents compared the same way.
- **Preview = record:** for one record of every kind, the preview against the document of the record
  **created from the same request**, compared by page. Run it with every switch that makes a value
  visible (a "show price" flag off hides exactly the value most likely to differ).
- **Coercion:** the pure function against a temporary copy of the real table, in the session mode
  the application uses; the rows become the unit test's fixtures.
- **Nothing stored:** row counts of the record, link, cart **and** side tables (the translation
  registry) before and after a batch of previews with distinct inputs.
- **Hostile shapes:** an array-shaped value of every contract parameter, by every verb the action
  answers.

## Related

- `ROUTE_A_VARIANT_THROUGH_A_SHARED_WRITER.md` — the type classifier that keys on a link row.
- `LIST_ENDPOINT_OVER_A_SINGLE_TARGET_EVALUATOR.md` — the same move for a read that lists what an
  action would do: extract the evaluator, call it from both.
- `NEW_PARAMETER_ON_A_LEGACY_ENDPOINT.md` — status codes of a new action beside always-200 siblings.
- `skills/work/references/FALLBACK_HIDES_THE_BRANCH.md` — which template the walk really drew.
- `skills/review-loop/references/USER_TEXT_INTO_A_RENDERER.md` — what the renderer does with the
  text it is given.
