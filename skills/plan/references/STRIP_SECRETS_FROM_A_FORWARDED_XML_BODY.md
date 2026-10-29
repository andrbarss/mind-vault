# Strip secrets from a forwarded XML body — byte-exact, linear, fail closed

Load when a plan forwards a client's XML body to another system and must remove the credentials (or any secret
element) the client put in it, while keeping every other byte as received — e.g. a middleware that authenticates on
`<Username>`/`<Password>` in the body and must not pass them upstream, where they are stored and served to admins.

## The design that held

1. **Remove text, then verify structure.** A DOM round-trip changes bytes (declaration, attribute quoting, whitespace,
   empty-element form), so remove the elements from the raw string, then re-parse the result **with the same parser
   and flags that authenticated the request** and check: it parses; the root is the same; none of the secret elements
   is left as a direct child (read with the same accessor authentication used, e.g. `isset($doc->Password)`); the
   other direct children are the original's, in order. A span removed from the wrong place (a comment, a deeper
   element, a CDATA section) leaves the authenticated element in place or breaks the parse, so the check catches it.
2. **Fail closed.** When removal or verification fails, refuse the request and send nothing — do not fall back to
   forwarding. Record the refusal as a deliberate difference from the legacy (which forwarded everything) and name the
   cost: the upstream state stays stale until the client's next message.
3. **Log the failed check, never a value.** A reason code (`doctype`, `left_Password`, `complex_Username`) is enough to
   diagnose; the body and the secrets stay out of the log.

## The bypass a structural check cannot see

Verification compares *element structure*, not the *values* that were removed. A DTD internal entity moves a value out
of the element:

```xml
<!DOCTYPE R [<!ENTITY p "the-real-password">]>
<R><Username>u</Username><Password>&p;</Password>…</R>
```

The parser expands `&p;`, so authentication succeeds; the removal deletes `<Password>&p;</Password>`; every structural
check passes — and the forwarded body still carries the password in its DOCTYPE. A partial form (`test-&p;`) works too.
Found by an adversarial reviewer, not by the architect pass or the review bot.

**Rule:** fail closed on **any** DOCTYPE in the original document (`dom_import_simplexml($doc)->ownerDocument->doctype
!== null`), and on a removed element whose text holds an entity reference other than the five predefined ones and
numeric references. A client that never sends a DTD loses nothing. Then add the case to the parity harness as a
decided difference, so a regression shows.

## Linear time on hostile bodies

A lazy pattern such as `<Name(?:\s[^>]*)?>.*?</Name>` with `/s` returned `null` ("backtrack limit exhausted") on a
7.5 MB body, and `<Name(?:\s[^>]*)?>[^<]*</Name>` was still **quadratic** on a comment holding 20 000 × `<Name ` (4.6 s,
200 KB, and it succeeded). Use possessive quantifiers and an anchored continuation:

```php
preg_match("#<$name(?=[\s/>])[^>]*+>#", $body, $tag, PREG_OFFSET_CAPTURE);   // the first start tag, linear
// self-closing when the tag ends in "/>"; otherwise the content must follow immediately:
preg_match("#\G([^<]*+)</$name\s*+>#", $body, $rest, 0, $tagEnd);
```

Take only the **first** candidate per name; if it is not removable, fail closed (the verification would refuse anyway,
and scanning on to later candidates reintroduces the quadratic case). Use byte patterns (no `/u`) so any
ASCII-compatible encoding works; `/u` returns `null` on Latin-1. A test that pins the time must use a size where the
old pattern was slow *and succeeded* — at a larger size it fails fast on the backtrack limit and the test cannot tell
old from new.

## What still fails closed (and what is forwarded as sent)

Fails closed: any DOCTYPE; duplicate root-level secrets; CDATA, markup or a comment inside a secret element; the
first `<Name` in a comment, PI or deeper element before the real one; `/>` inside an attribute value; UTF-16/32
bodies (a byte pattern cannot match). Removed correctly: attributes (including `>` inside a value), whitespace and CRLF
inside tags, a default namespace, predefined and numeric references, a BOM, Latin-1 high bytes.

Forwarded as sent, by design: a value the sender *also* put elsewhere (a deeper element, a processing instruction, an
attribute). Only the authenticated root-level elements are the middleware's to remove; say so in the docs.

## Checklist

- [ ] Remove as text, verify by re-parsing with authentication's parser, flags and accessor.
- [ ] Fail closed: refuse and send nothing; record the difference and its cost; log the reason, never a value.
- [ ] Any DOCTYPE fails closed; an unusual entity reference inside a removed element fails closed.
- [ ] Possessive start-tag scan + `\G` content match; first candidate only; byte patterns.
- [ ] A timing test at a size where the old pattern was slow and succeeded.
- [ ] The parity harness compares the forwarded body after its *own* strip and refuses to let any entry decide a
      forwarded secret ([`../../work/references/LEGACY_REWRITE_PARITY_HARNESS.md`](../../work/references/LEGACY_REWRITE_PARITY_HARNESS.md)).
