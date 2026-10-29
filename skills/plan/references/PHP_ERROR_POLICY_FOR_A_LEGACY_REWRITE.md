# PHP error policy for a rewrite of a legacy app that hid every warning

Load when a plan rewrites a legacy PHP service that ran with `error_reporting(0)` (or `display_errors` swallowing
everything) onto a current PHP, and must copy what the legacy answered — or when it designs warning-to-exception
conversion, a fatal-error answer, or the tests for either; when it reads decoded upstream values with 7.4's semantics
(§ 5); when it writes XML text the way a legacy `SimpleXMLElement::addChild()` did (§ 6).

## 1. What `error_reporting(0)` was really doing

In the legacy, a missing array key, an undefined index or a bad string offset was a hidden notice: the code went on with
`null` / `''`, and the client received a record with an empty field. A rewrite that converts every warning into an
exception turns those records into errors. Where the input is one-shot — a pull feed that marks records delivered as it
answers — an exception after the upstream answered **loses** data the legacy delivered.

So the policy is split by phase, not global:

- **Before the upstream answered**: warnings and notices → `ErrorException`, fail closed (a refusal, nothing lost).
- **After a one-shot upstream answered**: run the mapping inside a tolerant scope that records each warning (file:line,
  never the message) and lets execution continue with the value the legacy got. Only a `Throwable` skips a record.
- **Deprecations are never converted**, only logged (once per file and line per request — a per-worker memo under
  prefork is effectively random). Otherwise the next PHP minor turns a library deprecation into a refusal on every
  request.

## 2. What the tolerant scope cannot copy

It gives the legacy value only for warnings that are **still warnings** on the new PHP. Several PHP 7.4 warnings are
`TypeError`s on 8.x (verified with a tolerating handler on both):

| Expression | 7.4 | 8.x |
| --- | --- | --- |
| `'abc' / 3` | warning, `0` | `TypeError` |
| `count(null)` | warning, `0` | `TypeError` |
| `number_format('abc', 2, '.', '')` | warning, `NULL` | `TypeError` |
| missing key | `NULL` | `NULL` (warning) |
| `'5 apples' + 1` | `6` | `6` (warning) |

Rule: code that copies a legacy coercion **casts explicitly**, as 7.4 did, with one test per cast, and those files do not
declare `strict_types`. Pin the limit with a test: a `TypeError` inside the tolerant scope propagates.

Install the error handler in the front controller (a bootstrap only `index.php` calls), never in the app factory, so a
test process never inherits it.

## 3. A fatal error still gets an answer

`register_shutdown_function` + `error_get_last()` lets a fatal (out of memory, timeout) write its log line — with the
request id and the upstream calls already made, which is what an operator needs to recover a lost record — and answer
the client instead of PHP's empty 500:

- **Reserve memory** at bootstrap (`$reserve = str_repeat("\0", 65536)`) and free it first in the shutdown function, or
  an out-of-memory fatal cannot even write its line.
- **`http_response_code()` refuses to replace the status after a fatal**: PHP has already set its 500 status line, and
  the call emits *"Calling http_response_code() after header('HTTP/...') has no effect"* — a warning, which your own
  handler converts into an uncaught exception, so the answer stays an empty 500. Use `header('Content-Type: …', true,
  $status)`: the third argument replaces the status line. Set the error handler aside around the emit
  (`set_error_handler(fn () => true)` / `restore_error_handler()`).
- Prove it live, not in a unit test: under the real SAPI, make one request exhaust memory inside a handler (a temporary
  front controller that defines the action class before the autoloader can load the real one works well) and read the
  status, body and log line. Opcache revalidates a swapped file only every `revalidate_freq` seconds (default 2) — wait
  that long after each swap, or the probe tests the old file.
- Set `zend.exception_ignore_args = On` (php.ini-production has it; a bare Docker `php:*` image does not): a fatal's
  stack trace in the server error log otherwise prints argument values, which can be guest data.

## 4. Testing the handler under PHPUnit

PHPUnit (10+, observed on 13) lowers `error_reporting()` to the unhandleable levels while a test runs and handles the
rest itself. A handler that respects `@` with `if ((error_reporting() & $errno) === 0) return false;` therefore reads
**every** warning as silenced in tests — conversion tests fail, tolerant-scope tests record nothing. In the handler's
tests, raise it around each test (`#[Before]`: `$this->saved = error_reporting(E_ALL)`, `#[After]`: restore) and say why
in a comment; production keeps the `@` check.

## 5. Reading decoded values as 7.4 did — one shim, no cast that warns

Under a warning-to-exception policy, every raw read of decoded upstream data is a refusal waiting for a shape the
legacy tolerated: `$entry['x']` on a string or an int, `(string)` / `.` on an array ("Array to string conversion"),
`trim(array)`. Route every read through one small class whose methods branch on the type and reproduce 7.4's *value*
without its warning. Measured on 7.4.33 against 8.5:

| Expression | 7.4 value | shim |
| --- | --- | --- |
| `"abc"['k']` (non-numeric key) | `'a'` (illegal string offset reads offset 0); `""['k']` → `''` | `offset()`: arrays by key, strings their first char, else `null` |
| `$int['k']`, `$bool['k']`, `null['k']` | `null` | `null` |
| `[] > 0`, `[0] > 0` | **true** | `greaterThanZero()`: any array → true |
| `"5abc" > 0` / `"abc" > 0` / `"0x1A" > 0` | true / false / false (8.5: `"abc"` and `"0x1A"` are true) | leading-numeric prefix as a number, else 0 |
| `(string) [1]`, `"x" . []` | `'Array'` (notice) | `'Array'`, no notice |
| `(string) 0.30000000000000004` | `"0.3"` — `precision=14` on **both** versions | plain cast |
| `(int) 1e20`, `(int) 2**63`, `(int) INF` | `7766279631452241920`, `PHP_INT_MIN`, `0` | **8.5 gives the same values but warns** "not representable as an int": `@(int)` for floats only, with a comment |

A narrowly scoped `@` is the right tool where the new runtime's value is already identical and only the warning is new:
the handler's `@`-check (§ 4) leaves it to PHP, and ErrorPolicy does not refuse. Never use `@` to hide a *different*
value. Prove the shim against the legacy, not against your own expectations: a parity case with deliberately hostile
shapes (string and int entries, array-valued fields, `"2abc"` ids) is the oracle; the unit tests only pin the table.

## 6. Writing text through SimpleXML the way the legacy did

A legacy that builds XML with `SimpleXMLElement::addChild($name, $value)` passes `$value` through libxml's entity
parsing, not as plain text. Measured on PHP 7.4.33 / libxml 2.9.10 (identical on 8.5 / 2.9.14):

| Value | Output |
| --- | --- |
| `A &amp; B`, `&#279;`, `&#x10FFFF;`, `&lt;b&gt;` | decoded and re-serialised: the receiving client reads `A & B`, `ė`, `<b>` |
| `Tom & Jerry` (bare `&`) | `<T/>` — the **whole element is emptied** (warning hidden by `error_reporting(0)`) |
| `&#0;`, `&#9999999;`, `&;`, `&#;`, `&#12` alone | `<T/>`; inside text only the reference is dropped (`x&#0;y` → `xy`) |
| `&#X41;` (upper-case X) | garbled to `X41;` |
| `&nbsp;`, `&foo;`, `&AMP;` | passed through **raw**: the document is no longer well-formed XML |
| a C0 control (not tab/LF/CR), U+FFFE, U+FFFF | `asXML()` warns "char out of range" and writes `<T></T>` (an empty *text node*, not `<T/>`); the rest of the document is intact |
| NUL | the text is cut at the NUL (C string) |
| `''` / no text | `<T/>` |

Rules for a rewrite that must copy the output:
- Decide the `&` cases with the owner — copying "valid references decoded, everything else escaped as text" keeps
  the only difference where the legacy is broken. Implement it as a scan that keeps `&amp;|&lt;|&gt;|&quot;|&apos;|
  &#d+;|&#xH+;` (code point allowed by XML 1.0) and escapes every other `&` before `addChild()`.
- A text with a forbidden character: write an element with an empty DOM text node
  (`dom_import_simplexml($child)->appendChild($doc->createTextNode(''))`) instead of passing it, so the bytes match
  and `asXML()` never warns.
- Attributes go through `addAttribute()`, which escapes `&<"` itself; U+FFFE/U+FFFF there still make `asXML()` warn
  while writing the legacy's exact bytes (`&#xEF;&#xBF;&#xBF;`) — silence that one call (§ 5's rule).
- `asXML()` with no encoding writes `<?xml version="1.0"?>` and every non-ASCII character as a numeric reference; the
  bytes depend on the libxml version, so pin them in a test that runs in the production image.

## Checklist

- [ ] Phase split written into the plan: fail closed before the upstream answers, tolerant after a one-shot answer.
- [ ] Deprecations logged, never converted; scoped per request.
- [ ] Every 7.4 coercion that is a `TypeError` on 8.x is an explicit cast with its own test; the propagation limit pinned.
- [ ] Handler installed by the front controller only.
- [ ] Shutdown function: memory reserve, log line with the upstream calls, answer via `header()`'s status argument.
- [ ] `zend.exception_ignore_args = On` in the image.
- [ ] A live fatal probe under the real SAPI; opcache revalidation waited out.
- [ ] Handler tests raise `error_reporting()` around each test.
- [ ] Every read of decoded upstream data goes through the value shim; `@` only where the value is measured identical.
- [ ] A hostile-shapes parity case checks the shim against the legacy itself.
- [ ] SimpleXML text: the `&` rule decided with the owner, forbidden characters as empty text nodes, the bytes pinned in
  the production image.
