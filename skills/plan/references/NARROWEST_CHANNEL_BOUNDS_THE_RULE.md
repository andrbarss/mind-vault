# The narrowest channel bounds the product rule — read every exporter's unit before locking the semantics

Load when a plan changes **what a price, a discount, an availability or a status means** and the value
reaches more than one consumer — a storefront, a partner feed, an OTA or marketplace export, a PMS
push. The owner's first phrasing of the rule is written for the channel they look at (the storefront);
the exports usually carry a *narrower* unit. A rule the storefront honours and a partner channel cannot
represent is a promise one channel cannot keep, and the discrepancy is found by a guest, not a test.

## The trap

The draft here added "if tonight qualifies, discount the whole stay" beside "discount tonight only".
Sensible on the storefront, where a stay is priced as a stay. The two OTA exports price **each date as
a one-night stay** — the export loop calls the pricing engine per day with the stay length fixed at
one, and neither wire has a length-of-stay rate or a promotion object. "Whole stay" had no
representation there at all; it would have been a storefront-only rule wearing a global name. The
owner dropped it the moment the export shape was on the table: *first (current) night only, for all.*

## The rule

Before locking semantics that several channels will carry:

1. **Enumerate the channels** that emit the value: every exporter, feed, push and read endpoint —
   including the ones nobody thinks of as a channel (a partner's periodic pull, a calendar badge).
2. **Read each one's unit** off the exporter's code, not its docs: the loop that walks the dates, the
   argument it fixes (`nights = 1`, one occupancy, one rate plan), whether the end bound is inclusive,
   what the payload can carry (a price per date; a rate per length of stay; a promotion object). Quote
   the lines in the plan.
3. **Set the rule at the narrowest unit** — or scope the feature per channel *explicitly* in the
   contract, with the channel names, so the storefront's richer behaviour is a documented extension
   and not an accident.
4. **Remove the wider variant strictly** when it is dropped: the flag, its wire key, its rows in the
   plan, the contract, the sibling repositories' ideas and the tests. A half-removed variant is the
   worst outcome — a later reader finds the richer rule in one document and ships it.

## Two corollaries

- **A category the channel never carries is excluded from the feature.** One discount type here is
  applied once and copied onto further nights by the storefront's cart maths, and the export engine
  never emits it as a price at all (it only reduces a headline figure passed as information). The new
  flag on that type would discount N nights on the storefront and none on the channel — so the flag
  is honoured for the one type both channels price identically, and the writer refuses it elsewhere.
- **The push cadence is part of the rule.** Read *when* each channel is written, not only *what*: a
  channel that is only ever pushed by a half-hourly full export cannot show a window shorter than
  that cadence, whatever the rule says. Either the feature pushes that channel itself on every
  boundary (see [`STATE_WATCH_ON_A_SHARED_CHECKOUT.md`](STATE_WATCH_ON_A_SHARED_CHECKOUT.md) § 5) or
  the plan states the lag as the channel's cadence plus its run time.

## How to discharge it

- One line per channel in the plan's Requirements Trace: unit, cadence, the file:line of the loop.
- A pin on the exporter's fixed argument (the `nights = 1` call) so a later change to the exporter
  re-opens the question.
- The owner's decision recorded with the evidence that produced it — the export shape — so the next
  request for the richer rule starts from the constraint, not from scratch.

## Related

- [`VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md`](VERIFY_ARCHITECTURAL_CLAIMS_AT_RUNTIME.md) — the
  general rule; this is its "what can the wire carry" instance.
- [`PRODUCER_ARGUMENT_CONTRACTS.md`](PRODUCER_ARGUMENT_CONTRACTS.md) — classifying the fixed argument
  the exporter passes to the shared producer.
- [`SCHEMA_CONTRACT_HANDOFF.md`](SCHEMA_CONTRACT_HANDOFF.md) — where the per-channel scope is written
  for the sibling repositories.
