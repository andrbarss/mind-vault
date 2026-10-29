# Never fail after a destructive pull

Load when a plan handles an upstream call that **marks records delivered as it answers**, with no confirmation step:
a "pull new reservations / orders / messages" endpoint whose rows are flagged synchronised before the response
leaves. Every failure of the middleware after that answer loses those records for good, so the usual "refuse on
anything odd" is the wrong default from that point on.

## The order of operations

1. **Log the ids from the raw body, before anything that can exhaust memory.** Use a digits-only pattern such as
   `/"record_id"\s*:\s*"?(\d{1,20})/`: digits cannot carry personal data, and the pattern works on a body that does
   not parse, for example a PHP notice in front of the JSON. Write it as its own log line straight away. An id list
   that lives only in the request's final log line is lost to an OOM kill or a segfault.
2. **Decode once.** A PHP array costs about 6.5 times its JSON (15,000 records: a 12.9 MB body, 83 MB decoded, the
   same on 7.4 and 8.5).
   - In the field case, an HTTP client wrapper decoded every 200 "for convenience", and the handler decoded the body
     again. 11,000 ordinary records exhausted 128M, a size the legacy answered.
   - Give the client an undecoded mode for this call.
3. **Raise the memory limit for that request only**, with headroom over the legacy's own limit.
   - `ini_set('memory_limit', …)` is reset at the end of the request.
   - Under PHP 8.5's `max_memory_limit`, the call warns, clamps and *returns the old value as success*. Read the
     limit back with `ini_get()` and log a shortfall; never let the warning become a refusal.
4. **Map, then write.** Read every value of one record into a value object before writing any of it. A record the
   legacy crashes on is then skipped whole and logged with its id, and the others are answered. Copy the crash
   conditions as explicit checks, not as caught errors, so the skips are exactly the legacy's crashes.
5. **A last-resort catch per record**: anything unforeseen also skips. Log the exception's class, file and line,
   never its message, which may carry data. Set the request's outcome to an error level, so a skipped record is
   visible.
6. **Generate unbounded output lazily.** A stay built from a zero date (MySQL `0000-00-00` through
   `date('Y-m-d', strtotime(…))` gives `-0001-11-30`) is 740,000 nights. Build them with a generator straight into
   the document, never as an array.

## Budgets: only above the legacy's own limit

A cap on the answer size is a difference from the legacy. It is safe only where the legacy loses the whole answer
anyway. **Measure that over HTTP, not from the CLI.**
- From the CLI, the legacy answered 740,000 nights.
- Under Apache it sent an empty HTTP 200 above about 690,000–720,000 nights in total (1, 2 and 4 records), and lost
  every pull from 20,000 ordinary records.

Set the budget above that, check that the rewrite answers the budget at its own limit (1 to 10 records), and record
it as a decided difference. The budget counts nights, not bytes, so state which bound bites first.

## Checklist

- [ ] Ids logged from the raw body with a digits-only pattern before the decode; no personal data in any line.
- [ ] One decode; the client does not decode this call.
- [ ] A per-request memory limit, read back after setting it.
- [ ] Map then write; legacy crash conditions as checks; a catch-all skip logs class/file/line only.
- [ ] Unbounded per-record output generated lazily.
- [ ] The legacy's capacity measured over HTTP (records and size); any budget set above it and decided.
- [ ] A test at a realistic large pull (tens of thousands of records) under the production memory limit.
