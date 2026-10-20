# Suppressing a customer-facing send, and telling your own team instead

Load this when a plan changes a shared send method so that it lists less, or sometimes sends nothing at all. Typical cases: a confirmation, receipt or notification that must leave out stale items (an ended stay, an expired or cancelled line) and must not go out when nothing is left. The usual ask: "if there is nothing to send, don't send — report it to our support, not the customer's."

The change looks like one `if` around the senders. The traps are around it.

## 1. Scope the filter per message purpose, not per method

One send method usually renders several templates, chosen by its callers. Each template has its own job, and "live" means something different for each:

- **The confirmation after payment** lists paid / active items.
- **The pay-later notice** is sent *before* payment, so its items are by design in an awaiting-payment state. A paid-only filter empties every one of them.
- **The staff alert** ("a cancelled item was paid — contact the customer") exists *to show* the cancelled row. Filter it and it becomes useless; suppress it and staff lose the alert.

Decide the rule as a map, template → admitted states, at plan time. A template absent from the map is unfiltered and never suppressed. That is the safe default for a template a later caller adds. Then, for each caller, read the state its items are in **at the moment it calls the send**, and write the table into the plan:

| caller | state at send time |
| --- | --- |
| payment callback | items just claimed paid, or a cancel that landed after the claim |
| pay-later setup | awaiting payment, by design |
| manual re-send | anything, including an unknown id |

A caller whose items can legitimately sit outside its template's set (an "add-on confirmed" action reachable on an unpaid cart) changes behaviour. Read whether that path can do anything useful on such a record. Then either give it the right template, or record the consequence for the owner.

## 2. "Expired" is a claim about a column — read every writer of it

A legacy table often carries an `expired`-style flag beside its status. Before filtering on it, list every writer:

- the expiry job
- the cancel path
- the restore path
- a late-payment "reopen" path that revives a cancelled row and sets it active again **without clearing the flag**

That last one makes "active + flagged expired" a *paid* item. Judge expiry by the status the expiry path writes, plus the stay / validity date, not by the flag. Read the date column's type: a `DATETIME` that carries the checkout hour makes "ahead" end at checkout, not at midnight. Compare on the clock that writes it.

## 3. Decide after the inputs load, before any effect

Put the "anything left?" decision **after** every input it judges is loaded: the filtered items, the other content kinds the message can carry (vouchers, add-ons, events). Put it **before** the first effect: the totals computation if it writes, the render, attachment generation, the first sender, and any "sent" bookkeeping (an invitation-sent flag, a log row). Verify that everything between the seam and the render is a read.

- If the inputs are locale-enriched, the decision sits after the locale switch, and the suppressed path leaves through the same locale reset as the send path.
- "Nothing to send" means **every** content kind is empty, not only the one you filtered. A voucher-only cart still sends.

## 4. The internal alert: best-effort, fixed call shape, logged either way

- **Never throw from the suppressed branch.** It runs inside payment callbacks. An exception there, after the payment was confirmed, turns a suppressed e-mail into a failed callback (retries, a 500, a lock left held). Wrap the alert in `try` / `catch (Throwable)`, not `Exception`: a `TypeError` from a non-string request id is an `Error`.
- **Pin the call shape of the house "mail support" helper.** These helpers often have surprises:
  - the message argument becomes the **subject**, with newlines stripped
  - a debug flag appends `$_POST` / `$_GET` / server variables (guest e-mail and phone, the API token) to the body
  - the body is sent as HTML with only `nl2br`

  So pass a constant subject, debug off, and a body built from ids / states / dates only. Build the body **inside** the `try`.
- **Reduce request values that reach the HTML body** (the record id, the action / route name — some routers dispatch a path segment that carries extra punctuation) to the characters they are made of.
- **Log one line whether or not the alert went out** (`alert sent` / `alert failed: <message>`). On a dev stack without mail, the log line is the only evidence. JSON-encode request values with an invalid-UTF-8 substitute flag, or a bad id blanks the line.
- **Tell the caller.** A manual re-send endpoint answers with a distinguishable outcome. Decide the status code with the owner and write it into the API contract.

## 5. Readers of the filtered list

- **A view that reads the list positionally** (`items[0]['company_name']`, `items[0]['expiry']`) breaks when the filter drops the first row and keeps keys. Re-index the filtered list.
- **Totals computed by the shared service over the whole record.** Keep them unless the owner decides otherwise, and write down that they can now include an item the message no longer lists.
- **Sibling senders.** The same list and the same dead guard are often copied into other senders: a queued variant, a REST client controller. Name them as out-of-scope follow-ups, and keep the policy class host-agnostic so they can reuse it.

## 6. Verify the effect, not the status code

When the change removes a send, the HTTP status is a weak oracle: a dev stack without mail answers the same 500 before and after on every path that still sends. Record the effect instead. Use a walk-only stand-in for the sender class, or a file transport, as `skills/work/references/WALK_A_BATCH_DRAIN_ON_A_PRIVATE_COPY.md` § 3 describes. Compare per row, before vs after:

- recipients
- attachment count
- the items listed in the rendered body
- the alert body

Rows worth having:
- **past-only** — before: mails; after: none + alert
- **unknown id** — before: empty mails; after: none + alert
- **mixed live / ended** — before: both listed; after: only the live one
- **all live** — identical
- **one other content kind only** — byte-identical body
- **the alert transport failing** — logged, reply unchanged

## 7. The sibling operations' published contracts

Changing what a shared private send method does falsifies the description of **every public operation that calls it** ("then ALWAYS sends the confirmation"), not only the one the ticket names. Grep the method's call sites and update each caller's API description in the same PR. `skills/review-loop/references/common-review-findings.md` keeps the review-side entry.
