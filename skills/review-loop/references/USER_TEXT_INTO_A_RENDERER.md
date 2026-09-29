# User text into a rendering library — the lens reads the library, not only the diff

Load when a PR **adds or moves a path by which text typed by a user reaches a renderer**: a PDF
library fed HTML, a template engine, a document or spreadsheet generator, a mail composer. "Moves"
counts: extracting the rendering of stored records into a shared class puts the old exposure in the
diff's reach for the first time.

## Why the engine and the author both pass it

The diff shows a string handed to `write(...)`. What the library does with markup in that string is
in a vendored file nobody has opened in years. An engine reviews the diff; the author knows the
output looks right. Field case: a PDF library bundled at a ten-year-old version read a tag of its
own in any HTML as **a call of one of its methods, with the tag's parameters passed to `eval()`**.
Greeting text typed by a customer was printed as HTML by every template. The engine's full review
was clean; the owner had already decided to leave markup in the text unstripped so that a preview
would equal the stored document. The correctness lens found it because its prompt asked one
question.

## The question for the correctness lens

> The templates print *these fields* into markup handed to *this library*. The owner has decided the
> text is not stripped — do not re-litigate that. Tell me concretely **what a holder of the
> credential can reach through this path**: read the library's parser for the markup it accepts.

Asking "what can be reached" instead of "is this safe" produces a finding or an explicit "read the
tag handlers, nothing beyond drawing". Add the instruction that made the proof harmless: **show it
with a parameterless, side-effect-free method** (a page break changes the page count) and send
nothing that carries parameters.

What to read in the library:

- tags or directives that are **not markup**: method calls, includes, expressions, macros;
- attributes that are **fetched**: image and link sources (local files, internal hosts);
- anything passed to `eval`, `include`, `unserialize`, a shell, or a callback by name;
- the version and its changelog: a later release often gates the feature behind a constant that
  defaults off — which tells you the vendor agreed.

## Closing it

- **Both places.** Disable the handler in the library **and** remove the construct from the text at
  the one entry every caller shares. Either alone leaves a way back: the library is replaced on
  update, the filter misses a spelling.
- **One entry.** Put the removal where stored records and new paths both pass (the function that
  builds the row a template draws), so a preview still equals the stored document.
- **A filter that loops until stable**, matches case-insensitively, takes the unclosed form, and
  falls back to byte matching when the text is not valid in the expected encoding. Test the nested
  form that survives one pass.
- **Comment the vendored edit** with who, why, and "do not restore on update"; pin it with a test
  that reads the handler without its comments.
- **Inventory every copy of the library.** A second, newer copy may sit beside the first (a
  submodule, another directory), loaded by other templates and by admin views. Grep the `require`
  lines, count which templates load which copy, read the newer copy's switch, and pin that nothing
  in the application turns it on. If the copy is not part of the repository's files, its state on
  each server is a **deploy check**, and the documents must not say "closed" for what loads it.

## What stays open — say so

The decision covered one construct. What else the library does with markup (fetched images, links)
was not examined: write that sentence in the PR and the archive, and file it. A reviewer whose
session ended before two of its questions were answered reports them as **unanswered, not clean**;
carry that wording into the hand-back unchanged.

## What the preview widened

Asked of any new path beside an existing one. The answer in the field case: the same credential and
the same text limits, so not *who*; but one request instead of two, **no stored row** that keeps the
input, and a documented read. "Nothing new" is rarely the whole answer.

## Related

- `VENDORED_UI_SHELL_REVIEW.md` — the defaults of a vendored front-end bundle.
- `LARGE_PR_INDEPENDENT_REVIEW.md` — when to run the lenses, and the increment review.
- `VERIFY_BOT_API_CLAIMS.md` — read the installed package, not the documentation.
- `skills/plan/references/PREVIEW_BEFORE_CREATE.md`.
