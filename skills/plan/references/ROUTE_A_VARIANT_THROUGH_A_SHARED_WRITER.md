# Routing a new variant through a shared writer — the join row that types the record, the presence-keyed arm, the untouched hash input

Load when a plan adds a variant of an existing sale / creation / submission ("the same thing, but with a
customer-chosen X") through a writer that several callers already share, and the obvious route is "reuse
the branch the writer already has for the no-parent case". Four traps, all field-observed on one
feature: a gift-coupon API that had to accept a customer-chosen amount for a coupon that was always
priced from its parent service.

## 1. The record's *type* may be derived from a join row, not a column

The first design ("send no parent, the writer already takes the caller's price then") read correct at
the writer: `parent_id > 0 ? parentPrice() : callerPrice()`. It was wrong two modules away. The record's
type classifier answered "amount coupon" **only when a row existed in the parent link table**, which the
writer inserts only for `parent_id > 0`. Without the link row the same record classified as a
*procedure* coupon — and the payment gate (`type != procedure`) refused it as reservation payment while
the PDF renderer took the procedure branch. Nothing in the writer, the columns or the price hinted at
it; the classifier lived in a getter with twenty readers.

Before choosing the "no parent" route: **grep the type classifier of the record and read what it keys
on.** If it keys on the existence of a child / link row, or on a nullable FK, the "no parent" variant
is a *different type* to every downstream gate, however identical its columns look. Then list the gates
that branch on the type (payment acceptance, rendering, partial use, reporting) and decide the variant's
type *first*; the route follows from it. In the field case the answer was "keep a real parent" — one
tenant-designated parent row, named by a configuration property, sold at the custom amount.

## 2. Key the new arm on the *presence* of the new field, so the siblings are untouched by construction

A shared writer with N callers is a sibling family (the self-sweep rule's trigger 6). Adding a third arm
to its price rule must not change the value any existing caller gets. The safe shape:

```text
price = has(custom)  && valid(custom) ? custom
      : parent_id > 0                 ? parentPrice(parent_id)
      :                                 callerPrice
```

keyed on `array_key_exists('custom', entry)` — *presence*, not truthiness — because the sibling callers
never put the key in their payload, so their path is provably unchanged without reading them. Then
still count the callers (the plan said three; the architect found a fourth, a free-coupon confirmation
that re-sends a virtual record's `getData()`) and pin the count in a test, so a fifth caller is a red
test rather than a silent new member of the family.

## 3. When a hash or idempotency key derives from a value's *text*, the existing arm must return it untouched

The writer's remote code was `MD5(id . createdAt . price . validTo)` over `$data['price']`. The parent
arm returned the DB's DECIMAL **string** (`'20.00'`); a "harmonising" `round((float) …, 2)` on the way
out would have produced `20` and changed every legacy hash without failing a single behavioural test
(the code is compared against the stored column, not recomputed). Rule: an arm that feeds a hash,
signature, checksum or dedup key returns the producer's value **as it is**; pin it with `assertSame`
on the exact string, not `assertEquals` on the number.

## 4. Give the decision its DB facts as lazy callables

The variant's refusal table needs two facts the legacy path never needed ("does the designated parent
exist", "what is its minimum"). Passed as values, they are read on every legacy request the moment the
feature is configured. Passed as closures, the legacy row reads nothing — and the unit test proves it
with callables that fail the test if invoked. The same shape as the `parentPrice` callable in § 2: the
pure decision class owns the truth table, the controller owns the reads, and each read happens only on
the row that needs it.

## 5. Two smaller rules the same feature paid for

- **A numeric-string gate must check finiteness and a ceiling.** `is_numeric('1e999')` is true (PHP);
  `parseFloat('1e999')` and `float('1e999')` are `Infinity` / `inf` in JS and Python. `INF > 0`,
  `round(INF, 2) === INF`, `INF < min` is false — an infinite amount passes *every* comparison and
  reaches the INSERT (stored as 0 under a lax SQL mode, a 500 under a strict one). Put `is_finite()`
  and a technical ceiling that fits the DECIMAL column at the single gate both the decision and the
  writer use; test `1e999`, `NAN`, twenty digits, ceiling + 1 cent.
- **"Listed ⇔ sellable" needs one shared gate.** When the storefront listing filters by a price row
  valid today and the sale reads the same row for its minimum, "no row" must refuse the sale
  (misconfigured), or the variant is sellable-but-unlisted. Name the filters the listing applies that
  the sale does *not* (active, expiry, internal, stock) instead of claiming equivalence.
