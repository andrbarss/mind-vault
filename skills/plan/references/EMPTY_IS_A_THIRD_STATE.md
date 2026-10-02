# Empty is a third state — a field that "always saves 0" is coerced on three layers

Load when a plan starts from **"the field cannot be left empty — it always comes back as `0`"**
(or `""`, or today's date, or `false`): a numeric or text column that is nullable in the schema, an
edit form that shows it blank, and a stored zero after every save. The user reads it as one bug in
one place. It is usually the *same* coercion applied independently on three layers, and the fix on
the client alone is right only once you know what `NULL` means to the thing that reads the column.

## 1. Find out what `NULL` means before touching the writer

Grep the **consumer** of the column first — the code that reads the row to do something (price a
sale, build a document, decide a limit), not the API that stores it. The field case: a coupon-sale
path copied three extension-coupon values from the product row and, when a tenant flag was on,
replaced a `NULL` / `""` value with the tenant default; a stored `0` was neither, so it **blocked
the default**. `NULL` meant *inherit*, `0` meant *explicitly none* — a third state the UI could not
express. That decides the IDEA's priority and what "fixed" means (empty must reach the row as
`NULL`, not as a sentinel), and it answers the data question (§ 5) before anyone asks it.

If the consumer treats `NULL` and `0` alike (`empty()`, `!value`), the bug is cosmetic and the plan
shrinks to "show empty for `NULL`".

## 2. The three layers, each one silent

Trace the value from the input to the row and name which layer manufactures the zero. Expect more
than one:

| Layer | Mechanism | Tell |
| --- | --- | --- |
| **Client model / serializer** | a typed numeric field converts empty to `0` unless told nulls are allowed (ExtJS `type: 'int'` without `allowNull`; a DTO with `int` not `?int`; a form library's `valueAsNumber` → `0`) | a `NULL` row *displays* as `0` on load — the conversion runs on read too |
| **API validation** | the framework skips non-implicit rules on an empty string (Laravel's `nullable|integer` never sees `""`; Django's `blank=True` on a nullable field); no normaliser turns `""` into `null` (no `ConvertEmptyStringsToNull`-style middleware in the stack) | `""` passes validation and reaches the persistence layer unchanged |
| **Database** | non-strict mode coerces `""` to `0` / `0.00` with a warning nobody reads (MySQL `strict => false`); the column is `DEFAULT NULL` so the schema looks innocent | the schema dump says nullable; the rows say zero |

Two consequences for the plan:

- **The client fix is sufficient when the API accepts `null`** (by the code: mass-assignment lists,
  casts, rules), and then there is no deploy order. Say which layer is the fix and which are
  hardening, and keep the hardening (an API-side `""` ⇒ `null` normaliser, the missing rules) as a
  companion for the *other* writers of the same columns — there is usually a second client.
- **The negative "nothing in the backend forbids `NULL`" is a claim about three places**: the
  schema, the model's write guard (`$guarded` / `$fillable` / casts), and the rules. Cite all three.

## 3. Measure the payload through the production seam, not the bare object

A bare `new Model()` serialised in a test is not what the window sends. Edit forms write back every
field before save (`form.updateRecord()`, `form.getValues()`, a `serialize()`), **on a new record
too**, and an empty text input writes `''`. So the create column of the "today" table is the payload
*after* that step. The field case: the capture said "service creates leave `NULL`; the zero appears
on the first edit" — measured on the bare object; through the window every create already sent
`""` ×3 and stored zeros. The architect caught it only by driving the real form. Write the
before/after table with that column measured through the seam, and make the first spec row assert
both forms (bare, and after the write-back) so the count is unchanged and the seam is pinned.

## 4. Nullable, by the field's existing type — not by a new type

Two traps when choosing the declaration:

- **Do not type a decimal as a number when the UI accepts a decimal comma.** Number parsers strip
  thousands separators: ExtJS `Number.parse` strips `,` and turns a typed `3,5` into `35` — a tenfold
  silent error in a price. Keep the field as text and add an *empty ⇒ `null`* convert that returns
  every non-empty value untouched (no trim, no cast — `0`, `'0'`, `'0.00'` are values).
- **Do not retype an already-integer field as text** to unify the family; add `allowNull` (or the
  stack's equivalent) and leave the wire type as it was. Two declaration shapes in one family are
  acceptable when unifying them would change a non-empty wire value somewhere. State the resulting
  asymmetry (garbage in the typed field reads as "cleared"; in the text field it goes out raw and
  the API answers) and pin both in the spec table.

One normaliser for the text shape (a util the fields call at convert time — a direct reference in
a class literal is evaluated at parse time, before the util loads), not N inline lambdas. Note
that on an untyped field the "allow null" flag is a marker and the convert is the mechanism: a
verification grep must look for the convert, not the flag.

Dirty tracking changes with the shape: a typed field equates the loaded `30` with the input's
`'30'`; a text field does not, so a populated row re-sends its integers as strings on every save.
Pin that as "pre-existing, accepted" rather than claiming "nothing modified" for the whole family —
and fixture with the **producer's** read shape (a typed-integer API versus a string-only one), not
the shape that makes the row green.

## 5. The rows already holding an accidental zero

Every row the client created holds the sentinel. A deliberate `0` ("no extensions allowed") and an
accidental one are indistinguishable in the data, and the consumer in § 1 gives them different
meanings. The plan does not reset data; it ships a read-only sizing query per tenant and makes the
reset the owner's call. Say in the user-facing note that the stored zeros stay until an admin clears
the field.

## 6. Verification that can fail

- A per-model truth table — create with empty fields, `NULL` loads as, cleared from `NULL` (sends
  nothing), cleared from `0` (sends `null`), populated re-save, whitespace / comma / garbage — green
  for every member of the family, red-first on the previous declarations (expect the pin rows to be
  green before and after; say which).
- One row through the real form (unrendered is fine) so the `''` really comes from a text input.
- A runtime walk against the live API as the merge gate when the unit layer cannot see storage:
  create with empty fields → body carries `null` → reopen shows empty; and the paths the change
  alters — a create on the path with validation rules, a create on the busiest window, a rename of
  a populated row. Write the failure branch: if a row fails, the companion becomes a prerequisite
  and the deploy-order line changes.

## Anti-patterns

- ❌ Fixing the client without reading the consumer — the sentinel may be load-bearing (§ 1).
- ❌ `type: 'number'` on a price field in a locale that types `3,5`.
- ❌ Measuring the create payload on a bare object and writing "creates are unaffected".
- ❌ A blanket `UPDATE … SET col = NULL WHERE col = 0` — it flips every deliberate zero.
- ❌ Switching the database connection to strict mode as part of the fix — a repo-wide behaviour
  change with its own blast radius; name it as a non-goal.
