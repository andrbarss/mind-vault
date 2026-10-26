# A slow request on a legacy hot path — measure first, then split the fix by who can observe it

Load when a step makes an existing request faster (a booking, a checkout, a save) in a codebase
where the same models serve many callers, and "it must not change behaviour" is the acceptance
criterion rather than a test you can write.

## 1. Measure before touching anything

The slow part of a legacy request is rarely where the code reads as expensive. Three cheap
instruments, in this order, before any change:

- **The action's own timing line.** Many legacy actions already carry a per-stage timer
  (`startTiming(...)` / `stopTiming(...)`) that writes only when an env key points at a log
  file. Set the key on the dev stack (a prepended stub can set `$_ENV` for one request) and
  read the stages: the first run tells you which block to open, and the same line is the
  before / after evidence later.
- **A DB profiler probe controller.** A throwaway admin action that calls the block's
  sub-steps one by one with the request's arguments, under the framework's query profiler,
  and prints per step: wall time, query count, the most repeated query *shapes* (literals
  replaced by `?`) and the slowest statements. It separates "many queries" from "one slow
  query" from "no queries at all". Delete the file after the run; keep a copy outside the tree.
- **A scaling probe.** Run the suspect function for 1 / 3 / 10 / 17 days (or rows, or cart
  items) and read the slope. Linear PHP time with a flat query count is a per-item loop
  (one case: ~90 µs per room-day over every room of every hotel, three scans per request);
  a flat time with a growing count is an N+1.

What the measurement tends to find on this kind of path, in rough order of payoff: the same
aggregate computed twice by two helpers (one is a sum over the other); a loader called once per
day with a one-day range when it takes a range; a full recalculation of something a sibling
request already stores (a cart re-priced on every add); a scan over the whole house for a
question about one room type; a second full pass "to get the local price" that the first pass
already produced; and one SQL statement whose filter uses only the first column of a composite
index (`EXPLAIN` rows scanned ≫ rows kept).

## 2. Split every change by who can observe it

Before editing, sort each intended change into one of two columns and keep them apart in the
diff, the tests and the write-up:

| Equivalence-preserving | Caller-observable |
| --- | --- |
| The same result for every caller with less work: one range call instead of N single-day calls, one scan instead of two identical ones, a lean loader for a path whose readers were enumerated | A narrower window, a skipped step, a shortcut whose result could differ for some caller or tenant |
| Lands in the shared method, no flag | Lands behind a switch that **only the hot caller sets**, read in **one** place |

The switch: an instance flag on the model the action instantiates (`$model->leanRoomSearch =
true;` right after `new`), read once inside the shared method's branch. It is narrower than a
process-global registry flag (a sibling instance created inside a helper never inherits it), and
it needs no new parameter on a method that already has thirty. Shared helpers that need new
behaviour get **optional parameters whose defaults are today's behaviour**, so every other
caller's call site is unchanged and a grep for the non-default values finds the one caller.

For every lean loader, **enumerate the readers** before claiming equivalence: list the keys each
consumer on the path reads and check them against what the lean rows carry; a reader that
needs an enriched key is the reason the full loader exists. Return the full rows when a caller
already loaded them (a superset), in a separate memo so a lean row is never served to a
full-row reader, and drop both memos in the same cache-clear.

## 3. A skip guard is a claim about the skipped code

The riskiest optimisation is "do not run X when nothing could change". The guard encodes what
you believe X does; the independent review of one such guard found two gaps in a condition
that read as obviously sufficient:

- X applied a class of offers the creating path **refused by design** (its config lacked the
  cart list the offer gate requires), so a threshold in the guard (`> 1`) dropped the offers
  with the lowest threshold (`= 1`) that only X had ever applied. Read the gate in the skipped
  code; the guard's threshold must match *it*, not a reasonable-sounding number.
- X re-priced with the **cart excluded from occupancy** (a variable-rate exclusion the creating
  path does not apply), so with a sibling already in the cart the two prices legitimately
  differ. The guard needed "and the cart was empty before this item".

The procedure: open the skipped call and list every effect it has that the fast path does not
(a write it performs, an exclusion it applies, a gate it passes that the fast path cannot);
each item becomes a term of the guard or a reason not to skip. The same reading applies to an
**early return before an expensive scan**: it must mirror exactly the scan's own pre-gates (for
a rules engine: "enabled for this channel" ∧ "lists this pair"), and the **key shape of the
index the scan fills** decides what "targets" means (an index keyed by room type alone means a
rule in another hotel targets this one too — keep that reach, record the leak as a follow-up).

## 4. Oracles, and the honest gap

- **Same code, switch off / on.** One stack, two requests, the created row and its child rows
  compared field by field; the stub that makes the dev stack complete the request (see
  [`WALK_A_BATCH_DRAIN_ON_A_PRIVATE_COPY.md`](WALK_A_BATCH_DRAIN_ON_A_PRIVATE_COPY.md) for the
  prepended stand-in) stays identical in both. It proves the caller-observable column.
- **The equivalence column** is proven by the readers census (§2) plus the suite's executed
  doubles and source pins, and by the per-stage line showing only the targeted stages moved.
- **A skipped branch no fixture exercises** (no active automatic offer on the clone, say) is
  recorded as a named owner follow-up with the equivalence *argument* written out — not
  declared covered by a run that never entered it. The independent review will ask exactly
  which run entered the skipped branch; answer it in the verification doc before it does.

## 5. What the write-up must carry

The per-stage table before / after; the readers census for every lean loader; the two columns
with each change assigned; for each guard, the list of effects of the skipped call and the term
that covers each; the follow-up for every branch no oracle entered; and the follow-up migration
when the `EXPLAIN` showed an index that stops at its first column.

## 6. When the dev clone cannot show the cost, ship the timing line

A request that takes 8–20 s in production can take 50 ms on the dev clone:
- the clone's catalogue is a fifth of the size;
- nothing else is running;
- the slow part only appears under the tenant's real data and load.

Measuring on dev then optimises the wrong stage. Instead, make the per-stage line a production
instrument, and fix one stage per change:

- **Ship it off by default, on per tenant.** An env key read on every request, one line per
  request:
  - **file name:** names the tenant and the caller (`<tenant>_<channel>_<endpoint>_timings.log`),
    so one investigation reads one file;
  - **parameters:** non-personal only;
  - **failures:** a write failure is swallowed;
  - **stages:** every check and insert gets its own stage, plus `bootstrap` (request start →
    action) and an `untimed` remainder. A large `untimed` means a stage is missing.
- **A flow probe that produces comparable lines.** A small script that runs the real client
  sequence (create cart → book → cancel) N times with a fixed request, prints its own external
  timings, and tags its rows (`PERFTEST-…`) so they can be told apart from live traffic in the
  log. Before / after always means **the same request** with the same token, so the lines land in
  the same file.
- **Split the dominant stage before choosing its fix.** When one stage owns the time, add
  sub-stages to the same line, printed after their parent (`stage.child`) and **not** summed into
  `untimed`, and ship that first. The first split here named one getter as 66–87 % of every
  request, a getter nobody would have picked from reading the code.
  - **Warm a cache in its own sub-stage.** When the parent stage is a validator that warms caches
    internally, call those warm-ups from the controller, each in its own sub-stage, in the
    validator's own order. A warm-up can change the answer (see the stub trap in
    [`../../plan/references/SEED_ONE_ITEM_INTO_A_CATALOGUE_CACHE.md`](../../plan/references/SEED_ONE_ITEM_INTO_A_CATALOGUE_CACHE.md)),
    so pin the order.
- **One stage per change, each closed by a production before / after.** Make the production probe
  an owner-gated acceptance criterion of every change: deployed, the same probe run ≥ 10 times,
  the stage's median / p90 / max recorded before and after in the archive. Bucket the log lines by
  deploy time and by probe tag:
  - the probe-vs-probe comparison is the result;
  - the live lines between deploys are context (they carry the load spikes the probe in a quiet
    minute may miss).

  A sequence of three such changes took a request's median from 1.48 s to 0.17 s. Each step was
  chosen by the previous step's log.
- **Keep the line on after the fix** when the remaining question is load spikes: a quiet-minute
  probe cannot show that the 10 s outliers are gone, only weeks of live lines can. Record this as
  an explicit owner decision.
