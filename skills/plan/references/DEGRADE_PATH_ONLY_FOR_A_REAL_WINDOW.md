# A degrade path is only worth its machinery when the window it guards is reachable

Load when a plan adds a **per-column schema oracle**, an **exact-name strip**, or any other
"the tenant may not have this column yet" path to a consumer of a table another repository
migrates on a staggered schedule. The pattern this file tempers is a good one — a sort or filter
that names a column the tenant lacks is an `Unknown column` 500, and a read that is a wholesale
`SELECT *` hides that until the grid header is clicked — but its *shape* has a cost that compounds
per column, and the window it guards may not exist in the owner's practice.

## The shape that compounds

The first column gets: a contract mirror, a binding class over the generic schema oracle, a model
constant naming the column, a fixture that adds / conforms / drops / parks the column on the shared
dev database, a strip in the action that drops the sorter when the oracle says "absent", and
degrade tests that drop the column for real. The second column on the same table gets the same six
again — a second binding, a second constant, a second fixture, the two absent lists merged in the
action. The owner reads the diff and says: *each new field, new classes — and we never roll a column
back; we deploy the migrations first and the consumer after.*

That sentence is a **product statement about the deploy order**, and it decides the design. Ask for
it at `/plan`, before the first class exists:

1. **Is the state "consumer deployed, tenant not yet migrated" reachable under the owner's deploy
   practice?** Fleet migrate first and consumer after ⇒ the window is a human error, not an
   operating state. Rollbacks practised? ⇒ the window reopens on every rollback. Rollbacks not
   practised ⇒ it does not.
2. **What does the error cost when the window is a mistake?** For a *read*: a 500 on one grid click
   that heals the moment the migration runs, no data at risk (the consumer writes nothing). For a
   *writer*: a value the storage cannot hold — refused or silently dropped — which is a different
   question (keep the oracle for writers; see the last section).
3. **Does anything need to *distinguish* "column absent" from "column present, value empty"?** A
   wholesale read does not — the client reads an absent key as empty either way.

## Three shapes, and the default

| | Shape | Per new column | What it guards |
| --- | --- | --- | --- |
| **A** | **Generic per-list whitelist** — the action keeps only the sorters / filters naming a column in the tenant's *live column listing* (one memoised listing per request — the same call the oracle made) | **zero code** here; a typo or a column of a later release is ignored, not a 500 | the same 500, for every column at once, on this list only |
| B | No strip — pure pass-through, rely on the deploy order | zero code | nothing; a wrong order or a rollback is a 500 until the tenant migrates |
| C | Per-column oracle + exact-name strip (the compounding shape) | binding + constant + fixture + merged lists | the same 500, one column at a time; can also *name* the absent column |

**Default to A for wholesale reads.** It is the per-list form of the general "ignore an unknown
grid property" change — opted in one list at a time, so the API-wide behaviour change (an unknown
property is a 500 today on every other grid) stays a separate, owner-decided idea. State the
behaviour change on the list in the UI contract: a sorter the table cannot satisfy is ignored, the
rest apply, 200. Reserve **C** for the case where the window is real *and* something must act on the
column's absence by name — a writer that must refuse `true` for a flag the tenant cannot store,
a decision that branches on provisioning. **B** is honest when the owner says so, but A costs one
line and buys the typo case; B saves nothing A does not.

## Keep the degrade tests — they pin behaviour, not the class

Dropping the oracle does not drop its tests. The rows that drop the column *for real* and assert
"200, no key, the other sorters applied" are the behaviour; the fixture that drops the column stays
because the CI dump lacks the column and the tests need it. Two rows earn their place under A and
could not under C:

- **both contract columns absent at once** — under C this was the only row that told "the union of
  two oracles' lists" from "the second list alone" (one mutation reds it while the first column's
  rows stay green); under A it proves the whitelist over two absent columns;
- **a sorter on a column the table never had** — the generic form's own row; the exact-name form
  answered 500 here.

The oracle's own row ("the binding follows the column through drop and restore") becomes "the
*probe* the strip reads follows the column" — pin the thing the action calls.

## Reversing a shipped per-column shape is a rename-before-drop pair

When the owner's decision arrives after `/work` (the field case: read on the shipped diff), do not
delete the classes in the same commit that changes the action:

1. **Switch** — the action reads the live listing; the bindings are now unused by production code
   and still present; the whole suite is green. Add the generic form's own row here.
2. **Drop** — the bindings, the constants, the imports; fixtures name their column literally; the
   oracle rows re-pinned on the probe. The whole suite is green again, and the dev-database leg too.
3. **Mutations against the committed generic strip** — strip removed; whitelist keeping everything.
   Both red on the degrade rows (and on the *first* column's degrade rows, which the shared strip now
   covers — expected, say so).

The plan gets a dated section after its execution log: the options put, the one chosen and why, the
two commits, and **what it supersedes** — the design decisions, the suite count, the verification
grep, and every sentence in a sibling's shipped contract that the change makes false ("not a general
unknown-property strip" was true of the exact-name form). Those sentences get an *amended by* line in
the sibling's archive the same day, not at some later wrap.

## A principle a plan asserts must be grep-checked against the repo's own precedents

The first draft argued the per-column shape from a principle: "the generic oracle's documented
granularity is one owner contract per binding." The architect found a sibling that had **widened a
binding in place** with a second contract's column — free, because that binding and its constant were
*generically* named. The principle was contradicted in-repo; the real argument was the **rename
cost** of *column-named* classes (a rename-before-drop sequence plus re-pinned tests for no
behavioural change). Name the actual cost. A principle that a sibling already violates will be read
by the next planner as a rule and propagated; a cost can be weighed — and here, once the owner said
the window was not real, weighed to zero.

## For a writer, read what the framework does with the unknown key — before pricing the window

Question 2 above prices the window by its error. For a *writer* the owner's contract usually
predicts the database's answer ("every save answers `Unknown column`"), but the consumer's ORM may
never send the key. Read the write path before taking the prediction into the plan:

- **Laravel / Eloquent, `$guarded` a short list (not `['*']`):** `GuardsAttributes::isGuarded()`
  calls `isGuardableColumn()`, which lists the table's columns and treats any key the table lacks as
  *guarded*; `fill()` / `new Model($data)` skip it **without an exception**. On a tenant without the
  column a create answers 201 and an update 200, and the value is silently not stored. A value the
  validator refuses still answers 400 — but only where validation reads the posted body; an update
  that validates the merged model never sees the key at all. A raw `DB::table()->insert()` naming the
  column is the opposite case: the database error the contract predicted.
- So the window's cost for an ORM writer is a **silent discard**, not a loud error. That can change
  the owner's answer to question 2; when it does not (migrate first, admin after), write the degrade
  rows into the consumer contract **by the code** — the controller's validate line, the framework's
  guard method, each with `file:line` — instead of measuring with DDL on a shared table. Label them
  "by the code, not measured".

**The same cache bites the test suite.** `isGuardableColumn()` memoises the column list in a
`static` property keyed by model class — one request under PHP-FPM, the **whole process** under
PHPUnit. A fixture that `ALTER`s the table mid-suite, after any earlier test wrote that model, keeps
the stale list, and `fill()` keeps dropping the new keys. It reds only where the database starts
without the column (CI's fresh dump) and only in an order where a writer runs first — green locally
on a database that already has the column. Reset it right after the `ALTER`:

```php
$p = new ReflectionProperty(Illuminate\Database\Eloquent\Model::class, 'guardableColumns');
$p->setAccessible(true);
$p->setValue(null, []); // two-argument static form; the one-argument form is deprecated from PHP 8.3
```

Prove it with the full suite on a **fresh** test database, not a single file.

## Field case (2026-10)

An admin API over a multi-tenant booking store; the storefront's repository owns the table and
migrates tenants on a schedule. The first contract column (a guest ordinal) shipped the per-column
shape with a four-row degrade suite; the second (the guest's age band, an `ENUM`) was planned
column-for-column a week later and shipped the same way. The owner, reading the result, asked what
the two binding classes were for, said the deploy order is migrate-first with no rollbacks, and
chose A. The switch and the drop removed two classes, two constants and ~100 lines; the suite went
from N + 13 to N + 14 (the "column the table never had" row); eight mutations stayed red; the UI
sibling's condition for making its column sortable ("the backend release that carries the strip")
did not change. The lesson is not "never write an oracle" — it is that the oracle's premise is a
question for the owner, asked before the first class, and the answer is usually one line about how
they deploy.
