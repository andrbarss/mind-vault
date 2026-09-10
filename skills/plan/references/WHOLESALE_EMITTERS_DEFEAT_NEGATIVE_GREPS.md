# "Nothing reads this" — a wholesale emitter publishes rows it never names

Load when a plan, IDEA or review states that some **data** is unread, unused, internal, or not on any public surface — a new config row, a settings key, a feature flag, a column, a fixture. This is the negative-existence class of [`RULE_self-sweep-before-push`](../../../rules/RULE_self-sweep-before-push.md) trigger 5(7), with the specific search failure that makes it slip past a careful grep.

## Why the grep lies

The usual verification is sound-looking:

```bash
grep -rn 'my_new_setting' --exclude-dir=vendor .    # zero hits
```

Zero hits, so nothing consumes it. **Wrong** — because a *wholesale emitter* never names the thing it emits:

```php
$rows = $table->fetchAll($select)->toArray();     // no filter when no params
return array_combine(column($rows,'key'), column($rows,'value'));
```

One endpoint, one `SELECT *`, one map, and **every row in the table is on the wire**. The new row is published the moment the migration runs — no code change, no deploy, and no occurrence of its name anywhere in the source tree. The symbol-level grep was never going to find it.

Same shape in other stacks: a serializer with `fields = '__all__'`, a `SELECT *` cursor fed to `dict(zip(...))`, a settings blob returned as `vars(settings)`, `Model.objects.values()` handed straight to a response, a `/debug/config` dump, an admin export.

## The rule

To establish that data is unread, grep for **two** things:

1. **The name** — the direct consumers (`grep -rn '<name>'`).
2. **Wholesale emitters of its container** — the readers that take the whole table / model / settings object and pass it on without enumerating fields. Grep the *container*: `grep -rn '<table>\|<Model>' | grep -iE 'fetchAll|SELECT \*|values\(\)|__all__|to_?dict|array_combine|vars\('`.

Only both together support "nothing consumes it". If a wholesale emitter exists, the honest claim is narrower and worth writing precisely, because the distinction is load-bearing:

> No application code **branches on** this row. It *is* emitted — `<endpoint>` returns the whole table.

## Two consequences people get wrong afterwards

**The same value can have two types on two surfaces.** A wholesale emitter passes the storage representation through untouched (the string `"0"`), while a curated reader casts deliberately (`=== '1'` → a real boolean `false`). Both are correct; a consumer that assumes one shape from having seen the other is not. Say it explicitly in whatever contract the consumers read — this is the single easiest thing for a downstream developer to get wrong.

**The wholesale endpoint may be schema'd loosely enough that nothing needs updating.** `additionalProperties: {type: string}` (or an untyped map) means a new key needs no annotation edit and produces no artefact drift — so the generated-spec diff being clean is *not* evidence that the surface didn't change. Verify by probing the endpoint, not by trusting the drift check.

## A wholesale emitter is also a leak surface — check what else the map carries before a contract points a consumer at it

The same property that defeats the negative grep — the emitter publishes every row it never names —
cuts the other way the moment a plan or a cross-repo contract tells a **consumer** to load from it.
Field case: a write endpoint for a settings table was allow-listed by *type*, and the handful of
legacy rows writable by *name* were typed differently on some tenants, so the filtered read
(`?type=<kind>`) omitted them there. The contract's first draft said: "load the editor from the
**unfiltered** map and pick the legacy names out of it". Correct, and a leak: the unfiltered map is
the whole table, and the whole table also holds the readonly system rows — mail passwords,
payment-gateway secrets, API tokens — that a browser-side editor must never receive. Nothing new
was exposed (the emitter had always returned them); the contract was about to make a browser fetch
them on every editor open.

Before any plan, contract or README names a wholesale emitter as a consumer's data source:

1. **Inventory what else the emitter carries** — not the rows you need, the rows you don't:
   `SELECT <kind-column>, COUNT(*) … GROUP BY`, then `WHERE readonly = 1` / `is_secret` / the
   project's equivalent. If the answer includes credentials, the unfiltered call is server-side only.
2. **Put the merge where the secrets already are.** A back-end that reads the table directly (an
   admin API) selects the allowed rows and ships the browser only that projection; a browser that
   must call the emitter does so through a proxy that projects before any byte leaves it.
3. **Name the missing filter as a follow-up, not a workaround.** A `names[]` / `keys[]` parameter on
   the emitter makes the consumer's load one safe request; record it as an idea rather than widening
   the contract's recipe around its absence.

The reviewer's probe is one question: *"what does the unfiltered call return that the recipe does not
need?"* The architect pass that caught this asked exactly that; the plan's author had only checked
that the recipe **worked**.

## Cost of getting it wrong

A false "nothing consumes it" is cheap to write and expensive to unwind: it propagates from capture into the plan, into the shipped doc, into the migration's header comment, and into the cross-repo contract other teams build against — each copy re-asserting it without re-verifying, which is exactly the propagation trigger 5(7) exists to stop. Re-verify the negative **at every copy**, and when the answer changes, correct every copy including the one that reads as a settled decision.
