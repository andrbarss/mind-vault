# An operator-written list whose every accepted entry receives a secret

Load when a plan adds a **configuration value an operator types** — a list of URLs, hosts, webhooks,
mirrors, peers — and the code then **sends a credential to every accepted entry**: a shared key in a
query string, a bearer header, a signed callback. The validator is then a secret-distribution gate, and
three things that feel like polish decide whether it leaks: what "valid" means, what happens to the
entries that are *not* valid, and what the code says about them in a log.

Field case: a backend told its storefront to drop caches by calling `<base-url>/<method>?secret_key=…`.
The storefront grew a second domain, so an env key listing additional base URLs was added. The key was
**one literal shared by every tenant of the fleet**, so one mistyped entry in one tenant's env file
would have disclosed the credential every tenant's storefront accepts.

## 1. Drop, never repair

An entry that is not *plainly* what you expect is refused — never trimmed into shape, never
"normalised" into something the operator did not write. Repair is how `https://a.example:8]0/` becomes
port 8 and `https://a.example//b.example/` stays a path nobody intended. Refusals cost the operator a
glance at a log; a repair sends the secret somewhere they did not name.

Decide and test each of these as a **refusal reason**, not as cleanup:

- scheme allow-list; **no user-info, no query, no fragment** — test for the *presence* of the part, not
  its truthiness (an empty query `?` is present and empty);
- printable ASCII only, checked on the raw bytes **before** any parser sees them;
- host: per-**label** rules (a whole-string regex lets `a-.example` and 64-character labels through), a
  real dotted quad, or a bracketed literal validated as an address — never the integer / hex / short
  spellings an HTTP client will happily resolve (`2130706433`, `0x7f.1`, `127.1`, `010.0.0.1`);
- port: validate the **text** (`[1-9][0-9]{0,4}`), anchored over the whole authority — a parser that
  returns an integer has already forgiven `:+443`, `:00443`, `:` and a stray bracket;
- path: an allow-list of characters, no `.` / `..` / empty segment, no percent-encoding;
- entries equal to the primary, and duplicates, dropped silently; a cap on the count **and** on the raw
  length (checked before splitting — the value is parsed on a hot path).

## 2. The platform's URL parser is not a validator

It answers "how would I split this?", not "is this a URL?". Observed with one mainstream parser: the
"host" is *everything up to the first `/ ? # : @`* (`a.example&secret_key=X` is a host); a control byte
inside the host is rewritten to `_`; the "scheme" of `s3cret://x` is the secret itself; malformed ports
are coerced. Two consequences:

- **Send the URL you rebuilt from validated parts, never the entry.** Then the parser and the HTTP
  client cannot disagree about where the credential goes — the classic differential is closed by
  construction instead of by enumeration.
- **Platform versions disagree about what is "reserved".** An address filter treated the IPv4-mapped
  IPv6 block as reserved on a newer runtime and as public on the production one. Anything of the form
  "is this host internal?" should judge the address it will actually connect to — the IPv4 embedded in
  `::ffff:a.b.c.d` / `::a.b.c.d`, read from the bytes — so the verdict does not move with an upgrade.
  Run the truth table on the **production** runtime; a reviewer's probe on a newer one is a lead, not a
  result.

## 3. "Cleartext is fine here" must name the destination, not the primary

The tempting rule is "allow `http` when the primary is `http` — no new exposure". It fails when the
primary is an internal hop (`http://storefront:3000/`): a public `http://` entry beside it sends the
key across the internet in clear. Allow cleartext only to a destination that is itself internal (a
single-label service name, a private / loopback address), and say so in the operator docs.

## 4. Nothing of a refused entry may be rendered — not "a safe part" of it

The operator needs to know *which* entry was refused and *why*. The reflex is to log the entry,
masked. In the field case three successive renderings each leaked, each found by a different reviewer:

1. **mask the user-info** — missed a password containing `/`, `#`, `?` or a space, and any entry
   without a scheme (`user:pass@host`), and logged a pasted `?secret_key=…` whole;
2. **echo only the parser's scheme + host** — the parser's "host" was `a.example&secret_key=X`, and a
   scheme can be the secret;
3. **restrict that host to a host charset** — the charset allowed `_` (for container names) and the
   parser turns a tab into `_`, so `a.example<TAB>token` was logged as `a.example_token`.

The pattern: any rendering is a filter over arbitrary pasted text, and it has to be perfect. **Stop
filtering.** Return `position + reason + length` from the validator and nothing else — the refused text
does not leave the function, so no caller can log it later either. The operator has the config file
open; the position finds the entry. Pin the validator's public surface in a test so a `describe()`
helper cannot quietly come back, and keep every shape that leaked as a data-provider row.

When the same defect class comes back a **third** time in review, that is the signal to remove the
class rather than write the fourth filter (see
[`../../review-loop/references/LARGE_PR_INDEPENDENT_REVIEW.md`](../../review-loop/references/LARGE_PR_INDEPENDENT_REVIEW.md)).

## 5. The primary is compared against, not validated

The existing single value is what it is — it may carry user-info (a basic-auth staging site) or a host
the strict rules refuse (an underscore container name). Normalise it **leniently**, for comparison
only: otherwise an unusual primary silently switches off both the cleartext rule and the
"equal to the primary" drop, and the primary gets called twice.

## 6. Write down where the secret lands

Every accepted entry multiplies the sinks the primary already has: the queue row, the queue adapter's
log, a failure notification that quotes the URL, the destination's access log. List them in the
operator page, state that this feature's own log lines carry none of it, and file the sinks you find but
do not own as follow-ups — do not widen the change to fix them.

Two checks of your own diff, both learned the hard way: locate the secret **by key**, not by line
number (a merge shifted the file by one line and the check kept passing while grepping the wrong
string), and run it over the **whole branch diff**, not the last commit.

## 7. The operator page

- the format rules *as refusal reasons*, with the exact log line;
- a **preflight** the operator runs before listing an entry — from the host that will make the calls,
  with a time limit, reading the credential with a silent prompt and handing the URL to the client on
  stdin (history records the variable name; the process list shows nothing);
- "an empty log proves nothing": the refusal log is equally empty when the feature is inert — give a
  positive check (look for the queued calls);
- the blast radius of a process-level setting that overrides every tenant's own file;
- redirects: a client that does not follow them turns an alias into a permanent failure.

## Related

- [`FAN_OUT_THROUGH_A_SHARED_SERIAL_QUEUE.md`](FAN_OUT_THROUGH_A_SHARED_SERIAL_QUEUE.md) — what the
  accepted entries do to the queue that carries the calls.
- [`RAW_BODY_ENDPOINT_HARDENING.md`](RAW_BODY_ENDPOINT_HARDENING.md) — error text that echoes
  client-sized input, the request-body sibling of § 4.
- [`../../work/references/MUTATION_PASS_DISCIPLINE.md`](../../work/references/MUTATION_PASS_DISCIPLINE.md)
  — one mutation per refusal reason; a survivor on the production runtime only is a version difference.
