# A failed-login limit for an API whose callers are machines

Load when a plan adds a limit on failed logins (P4-style "per client and per source IP") to an endpoint that is
called mostly by **machines**, such as one integration or one PMS instance per customer, polling every few minutes.
In particular:
- the credentials travel in every request;
- several customers may share one egress address (a hosted product, a NAT, a reseller's server).

A lock there is not a nuisance for one person. It stops a customer's sync, and the machine does not read the refusal.
So the design question is not only "how many guesses", but also "who can lock whom out".

## Keys: who each counter may judge

The obvious design is an address counter and an account counter, with the account's usual address exempted. It locks
customers out without an attacker:
- The exemption ("this address logged in as this account recently") lapses after its time-to-live, or with a restart
  when the store is in memory.
- A customer with a stale password never logs in again, so it loses its exemption.
- From then on its failures, which come at its poll rate (measure it: dozens per window), go onto the **address**
  counter.
- That counter judges every login from the address, so it locks every other customer behind the same address. After
  a restart that is all of them, and none of them can ever earn an exemption again, because no login is accepted.

Assign keys by what the request names:

| The request names… | Judged by | Counted on |
|---|---|---|
| a registered account, from an address it logged in from recently (a *known pair*) | its (account, address) counter only | that counter |
| a registered account, from any other address | (account, address), and the account's counter | both |
| an unknown username | the address counter | the address counter |

- An address lock then stops enumeration and spraying, and cannot lock out an account. Nobody can log in with an
  unknown username anyway.
- The account counter bounds distributed guessing across all new addresses.
- **The price:** "per source IP" becomes per (account, address). One address gets N guesses per account per window,
  not N in total. Write that into the decision record; it is the owner's trade-off to accept.
- A wrong trusted-proxy setting makes every request come from the proxy's address. Make it a deployment gate: a live
  failed login must log the caller's address.

## Count atomically, release precisely

- **Check and reserve in one transaction.** A check before authentication and a count after it let a burst of
  parallel requests (one per worker process) all pass the check first. Reserve the failure in the same transaction
  as the check. Then keep it, or give it back, once authentication has answered. Measure it: N parallel failures
  must lock at exactly the limit.
- **Give a reservation back only within its own window.** Store the window start in the reservation and decrement
  `WHERE key = ? AND window_start = ?`. Otherwise a reservation made at the end of one window erases a failure counted
  in the next.
- **Count what tests a credential:**
  - count a wrong password, a wrong secondary code, or an unknown username;
  - do not count an empty or unparsable body, or a username no account could have;
  - do not count a request refused *after* a successful login (for example "HTTPS required"); give its reservation
    back;
  - record the known pair only for a fully accepted login.
- **A locked request is refused before the password is compared,** with the ordinary refusal's bytes. Otherwise a
  lock is a password oracle.

## The store

- **Under Apache prefork, choose SQLite on a tmpfs over APCu.**
  - APCu needs a PECL build, and the CLI gets its own segment. Neither an operator nor a test harness can read or
    clear it.
  - SQLite is in the PHP images and shared through file locks. A reset is deleting one file.
  - Use `journal_mode=DELETE`, because WAL's side files race with that delete. Use `synchronous=OFF` on a tmpfs, a
    `busy_timeout`, and `INSERT … ON CONFLICT … RETURNING` (SQLite ≥ 3.35).
  - Create the directory for the web user in the entrypoint. A tmpfs mounted root-owned is not writable by it. Derive
    the path from the same setting the app reads (one small CLI that resolves it), so the entrypoint, the reset and
    the app cannot disagree.
- **A cap must spare the keys nothing else judges.**
  - An attacker can create unbounded address keys (IPv6 /64s are cheap), so cap the new ones. Count them in the
    pruning pass, once a minute, so the cap is approximate.
  - Never apply the cap to account keys, which the registry bounds, or to a known pair. The pair is judged by nothing
    else, so once the store fills, an uncapped attacker at the customer's address would have no limit.
- **Fail open, and say what that costs.**
  - A broken store must not stop every customer's sync while the password check still stands. Catch `\Throwable` at
    the store's boundary, not inside the error-to-exception policy, and log one error per request.
  - But fail open can be induced: a request that waits past the busy timeout is counted nowhere. Measure a burst, and
    list the induced case as a residual.
  - The same applies to the timing gap. A locked request writes nothing, while a counted failure writes. Once the
    address counter for unknown usernames is locked, that difference shows which usernames exist.

## Test harnesses send from one address

A parity or smoke harness sends every case from one container address, including its deliberate wrong-password
cases.
- Count the failures **per key** for one run, and state the margin per key. The total is misleading.
- Clear the store after the stack is up, before each harness run.
- Make the harness print "an account at the harness address may be locked" when the rewrite answers with the login
  refusal where the reference did not.
- A smoke check that proves the lock must lock an account that no earlier check needs, and must run last.

## Checklist

- [ ] Each key's judge and counter written as a table; no address counter judges a registered account.
- [ ] The poll rate of a customer with a stale password measured, and the lockout walked: TTL lapse, restart, shared
      egress.
- [ ] Check-and-reserve in one transaction; the release bound to the window; N parallel failures lock at exactly N.
- [ ] Only credential-testing failures count; a refusal after login gives its reservation back; the pair is recorded
      only after full acceptance.
- [ ] The store shared across processes and clearable from the CLI; the directory created for the web user from the
      same setting.
- [ ] The cap spares account keys and known pairs, and a test fails without that exemption.
- [ ] Fail open logged, and the induced case and the timing gap written as residuals.
- [ ] The harness margin per key, a reset before each run, and the lock check run last.
