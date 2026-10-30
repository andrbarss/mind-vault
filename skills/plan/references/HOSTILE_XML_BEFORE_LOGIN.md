# XML parsed before a login — the bodies no parser flag stops, and how to bound the rest

Load when a plan parses an XML body from callers it has not authenticated, or reviews such an endpoint: when "we disabled
external entities" is the whole of the argument. `LIBXML_NONET` and no `LIBXML_NOENT` do stop XXE. They do not stop a body
of a few hundred bytes from taking a worker away. Numbers below: libxml 2.9.14, PHP 8.5 under Apache prefork.

## 1. What a parse can cost with every flag set right

Each of these held a worker until PHP's hard timeout (30 + 2 s) **killed the process: no answer, no shutdown function, no
log line**, only PHP's fatal on stderr. All before any login. The legacy service being rewritten did the same on the first and the last (measured).

| Body | Size | Why |
|---|---|---|
| Parameter entities in the internal subset (`<!ENTITY % a1 "%a0;%a0;…">`) | 1 KB | Expanded while the DTD is parsed, whatever the flags |
| The same in UTF-16 | 2 KB | A byte scan for `<!DOCTYPE` sees nothing |
| `<r a0="" a1="" …/>` | 1 MiB (0.75 s at 131 KiB, 14 s at 558 KiB) | The duplicate-attribute check is quadratic. **No DTD** |
| 250 nested tags of 254 `xmlns:n="u"`, then `<p:a/>` to 2 MiB | 2 MiB | A prefix lookup walks every declaration in scope. **No DTD, no long tag** |

Costs that do not kill, and still bite:
- **`(string)` on a mixed-content element** is quadratic in its child nodes: `<Username>` holding `xxx<a/>` to 2 MiB took
  2.66 s with no login, *after* the parse. Read a credential through a child-count guard.
- **The error list:** under `libxml_use_internal_errors(true)` PHP copies every error. 1.8 MB of `&x;` filled `memory_limit`.
- **libxml's own memory is outside `memory_limit`:** 567–709 MB per worker at 16 MiB of small nodes, 132 MiB at 2 MiB.
- An entity referenced from a credential expands at the *cast*, past any parse-time check.

## 2. The guard that holds: refuse before the parser runs

A check after parsing is too late for all of the above. Refuse on the bytes:

1. **`<!DOCTYPE` anywhere.** Measure first that real traffic has none. A literal one in a comment is refused too; simple beats exact.
2. **Make that scan sound:** it means something only in an ASCII-compatible encoding. Refuse a NUL byte (UTF-16, UTF-32 need one for `<`), libxml's EBCDIC signature (`4C 6F A7 94`), and a declared encoding off an allow-list. Read the declaration as the parser does: only at offset 0, after an optional UTF-8 BOM, up to `?>`. The list needs the spellings libxml honours (`UTF8`, `ASCII`, `latin1`, `ISO8859-1`, `cp1252`), not only the IANA names. Do **not** refuse on "the first byte is not `<`": plain non-XML text must keep whatever answer it had.
3. **A bound per tag:** `/<[^<=]*+(?:=[^<=]*+){256}/`, possessive, so linear. `<` cannot occur in an attribute value, so a `>` inside one cannot reset the count, which a pattern on `[^<>]` lets it do. Treat `preg_match` returning `false` as a refusal.
4. **A count of `xmlns`.** A substring count is enough where real traffic has none.
5. **A body limit before any read,** for every media type. Under mod_php that needs `enable_post_data_reading=Off`, or PHP reads any media type first. Send `Connection: close` on the refusal, or Apache drains the body on keep-alive with the worker held (10 s for a client that sends nothing, 0.00 s with the header). Read in small pieces: `read($limit)` allocates up front and fails on a worker near `memory_limit`. A body over 16 KiB also spills to the temp directory, up to twice, credentials included: put it on a tmpfs sized limit × 2 × workers.

Give these refusals their own text and outcome. A customer with a correct login and an unusual encoding must not read "authorization failed" at cut-over. They test no credential, so a login limit does not count them.

## 3. Assume the list is incomplete

The fixes above came one at a time, each after the previous one had looked complete: probing found the DTD, an architect review the attributes, an independent review the namespaces, and its re-review the cast. So:

- **Add a bound for what nobody has found:** `set_time_limit(5)` around the parse, restored in `finally` from the value read before it. That turned the same bomb from 32 s to 7 s. It bounds the *parse* only, and a hard kill still gives no answer. Say both in the docs.
- **Write the result as what was tried,** not as "no more such bodies exist".
- **Ask the reviewer for the slowest shape they can build, with its time.** That question found the namespace stack and the cast; "is the guard sound?" had passed.

## 4. Traps in the fix itself

- **Turning the error list off lets warnings out.** `LIBXML_NOERROR | LIBXML_NOWARNING` does not silence everything: a bad or duplicate `xml:id`, or a byte the declared encoding does not define, still warns. Under a warnings-to-exceptions policy that turned 23 of 105 odd bodies into internal errors, some on a correct login. Use `@` as well, and add parity cases: the suites were green.
- **A killed worker leaves its spilled body in the temp directory until a restart.** About 64 kills at 2 MiB fill a 128 MiB tmpfs, and requests over 16 KiB then fail. State it as a residual with its condition.
- **The limit's size is a memory decision,** not only a traffic one: pick it from libxml's cost per worker × workers, and keep the top of the setting's range under `memory_limit`.
- **Set each bound from real traffic and state what that proves.** One day of logs held 157 KB at most and no `xmlns`; it cannot prove the maximum, so make the limit a setting and have the pilot watch for the refusal.

## Related

- [`STRIP_SECRETS_FROM_A_FORWARDED_XML_BODY.md`](STRIP_SECRETS_FROM_A_FORWARDED_XML_BODY.md) — the same body forwarded upstream: any DOCTYPE fails closed there too.
- [`RAW_BODY_ENDPOINT_HARDENING.md`](RAW_BODY_ENDPOINT_HARDENING.md) — a cap "before the read" defeated by an argument expression.
- [`PHP_ERROR_POLICY_FOR_A_LEGACY_REWRITE.md`](PHP_ERROR_POLICY_FOR_A_LEGACY_REWRITE.md) — the warnings-to-exceptions policy this meets.
- [`../../deployment/references/NON_ROOT_READ_ONLY_PHP_APACHE.md`](../../deployment/references/NON_ROOT_READ_ONLY_PHP_APACHE.md) — the tmpfs and the workers.
