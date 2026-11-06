# Reading production logs without leaking the secrets they hold

Load before printing lines from a production log, a queue payload or a stored task into a
session, ticket or chat: post-deploy checks, live checks, incident triage. Many applications
write request data into their logs, and that data includes credentials.

## Where credentials hide

- **Exception logs that dump the request.** An error handler that appends `$_POST` /
  `request.body` / `params` to the stack trace writes the caller's API token in plain text, in
  the language's own serialisation: `'token' => 'abc…'`, `"token": "abc…"`, `token=abc…`.
- **Stored payloads.** A deferred task or a payment callback that saves "everything the request
  had" (often re-prefixed: `wp_token`, `callback_token`) keeps the credential for as long as the
  row lives. Anyone who reads the task in an admin queue page sees it.
- **Outbound request logs.** A client that logs the full URL logs every key passed in the query.
  Header-based keys are usually safe, unless the logger dumps headers too.

## The trap

A redaction filter written for one form misses the others. `sed 's/token=[^&]*/token=***/'` is
correct for a query string and does nothing to `'token' => 'abc…'` two lines further down the
same log entry. The secret then lands in the transcript, and, once one person has it, in their
copies, pastes and screenshots.

## How to read

1. **Extract, don't print.** Run the query on the host and copy out only the fields you need:
   one line per call, the method, a status, and the parameters by allow-list. Parse the payload
   (URL query, JSON) and print named keys. Never `tail` a raw exception log into the session.
2. **When you must print raw lines, drop by key name in every form.** Filter each serialisation
   the log uses — `key=value`, `'key' => 'value'`, `"key": "value"` — for every name that
   matches `token|key|secret|pass|auth`, prefixes included (`wp_token`). Prefer dropping the
   whole line to masking part of it.
3. **Check what you printed.** After a raw print, look for 20+ character alphanumeric runs next
   to a key-like name. If one got through, say so at once, name the credential and where it
   leaked, and recommend rotating it. Don't wait for the end of the task.
4. **Report the producer, not just the leak.** A log or payload that stores credentials is a
   defect in its own right. Raise it as a follow-up: redact in the error handler; keep only an
   allow-list in stored payloads.

## Related

- [`DEPLOY_TARGET_MAP.md`](DEPLOY_TARGET_MAP.md) — post-deploy verification reads these logs.
- [`HARDENING.md`](HARDENING.md) — host-level secret handling.
