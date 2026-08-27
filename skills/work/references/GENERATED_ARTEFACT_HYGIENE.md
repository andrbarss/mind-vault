# Generated, consumer-facing artefacts carry no process or environment provenance

Load when a `/work` item produces text that ships to people outside the sprint — an OpenAPI /
Swagger document, generated reference docs, a public CHANGELOG, a README section, CLI `--help`,
error-message catalogues. The rule: **the artefact describes the thing, never how the thing was
documented or where it was verified.**

## The leak

Agent-authored descriptions accumulate the sprint's vocabulary because it is what the author was
thinking about: idea / decision / PR ids ("IDEA-NNN D7", "PR #NNN review finding"), evidence words
("captured", "code-read", "verified live", "not observed", "probe"), and facts about the verification
environment ("on the dev clone (48 columns)", "no SMTP sink on dev", "`Class 'ZMQ' not found` —
the container lacks ext-zmq", "(redacted)"). A downstream project's generated API spec carried 171
such strings before a user pointed at two of them and asked for all of it to go. Consumers of the
artefact know neither the workflow nor the dev stack; to them the text is noise at best and a
false contract at worst (a `500` documented only because a dev container lacked an extension).

## The rule, applied

- **Process words out**: no idea / decision / PR / ticket ids, no "captured / code-read / verified /
  observed / probe", no review-bot references, no sprint dates used as provenance.
- **Environment facts out, behaviour in**: replace "on the dev stack every send throws" with the
  cause-phrased behaviour — "when the notification e-mail cannot be sent the exception propagates:
  HTTP 200 with the error-controller JSON under `Accept: application/json`". Drop facts that are
  only true of the verification host (row counts of a clone, missing extensions, timeout durations)
  and remove responses whose *only* cause was the host (a 500 from a missing dev extension).
- **Tenant / configuration behaviour stays** when phrased by its cause ("on the standard engine …",
  "when the tenant PMS is X …") — that is API behaviour, not provenance.
- **Redaction notes out**: the artefact's example simply does not contain the secret; it does not
  announce that it was redacted.
- **Provenance has homes**: source-level comments next to the annotation (a `// verified <date> via
  <captures>` marker), the schema file header, the archive docs, the commit message. Never the
  generated text.

## The guard

Add a suite test that walks every human-readable string of a fresh build of the artefact
(`description`, `summary`, `title`, help text …) against a banned-pattern regex and fails on the
first hit:

```
IDEA-\d{3} | \bD\d{1,2}[:,] | \bPR ?#?\d+\b | captur | code[- ]read | \bobserved\b | \bverified\b |
\bprobe | dev (stack|env|clone|tenant|container) | \bon dev\b | \bClass ' | ext-\w+ | redact |
on the wire | throwaway | fixture | review finding
```

Tune the list to the project's vocabulary, keep it case-insensitive, and state the rule in the
project's docs conventions next to the other structural guards. Two things the guard cannot see:
text the generator drops (e.g. a description beside a `$ref`) and prose outside the artefact — sweep
those by hand.

## Reviewer heuristic (curator PASS 1 / documentation agent)

When a diff touches an artefact that ships to outsiders, grep the *generated* output (not just the
source) for the banned list above; a single "IDEA-" or "captured" in an API description is a
finding of the same class as a hard-coded local path.

## Related

- [`CAPTURE_FIRST_API_DOCS.md`](CAPTURE_FIRST_API_DOCS.md) — the recipe whose evidence vocabulary
  most often leaks
- `rules/RULE_self-sweep-before-push.md` § doc-consistency sweep — the sibling sweep for docs that
  *are* process docs (plans, devlogs)
