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

## Cost of getting it wrong

A false "nothing consumes it" is cheap to write and expensive to unwind: it propagates from capture into the plan, into the shipped doc, into the migration's header comment, and into the cross-repo contract other teams build against — each copy re-asserting it without re-verifying, which is exactly the propagation trigger 5(7) exists to stop. Re-verify the negative **at every copy**, and when the answer changes, correct every copy including the one that reads as a settled decision.
