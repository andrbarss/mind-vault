# Vendored third-party UI shells — audit the defaults, not just the diff

A PR that drops a third-party browser UI into the app — Swagger UI / ReDoc for an API spec,
a Markdown or diagram renderer, an admin widget, an analytics or status dashboard — usually
ships as **a short HTML shell + a vendored minified bundle**. The shell is ten to thirty lines
of configuration; the behaviour lives in the bundle's *defaults*. A review engine reads the
diff and sees a small, tidy shell with nothing wrong in it. What it cannot see is what the
bundle does when a config key is **absent**.

Field-observed (2026-08-25): a push-triggered engine cleared such a shell on **three
consecutive SHAs** ("No issues found"). The independent reviewer that the loop dispatches as
its fallback read the vendored bundle and found that the UI's default layout renders an
**online validator badge** — on every page view it requests
`https://validator.<vendor>/validator?url=https://<tenant-host>/<spec-path>`, disclosing
the tenant hostname and the spec location to a third party, and having that third party
fetch the spec server-side (a red "ERROR" badge on VPN-only instances that read as "your
spec is invalid"). The project's own README, written in the same PR, said "the page must
not depend on a third party". The fix was one config key (`validatorUrl: null`) plus a test
asserting it — trivial once seen, invisible to a diff-only reader.

This is the third data point for the same lesson as
[`LARGE_PR_INDEPENDENT_REVIEW.md`](LARGE_PR_INDEPENDENT_REVIEW.md): an engine's clean pass is
*necessary, not sufficient* — here not because the PR is large, but because the risk lives
**outside the diff**, in code the reviewer would have to open on purpose.

## When this fires

Any PR whose diff adds or updates:

- a vendored bundle under a public/static dir (`public/`, `static/`, `assets/vendor/`) —
  minified `*.js` / `*.css` with a `LICENSE`/`VERSION` sidecar; or
- an HTML/template shell that instantiates a third-party UI (`SwaggerUIBundle(...)`,
  `Redoc.init(...)`, `mermaid.initialize(...)`, `<script src=".../vendor/...">`); or
- a config object for such a UI, even when the bundle itself did not change.

The check is **not** satisfied by an engine's CLEAN verdict on the diff. Dispatch (or run
yourself) an independent pass with the checklist below before the loop hands back.

## The checklist — what the defaults do when a key is absent

Read the vendored bundle (grep is enough — these are string literals) and the vendor's config
docs for the pinned version. For each item, either the shell sets it deliberately or the
review records why the default is acceptable.

| Probe | What to grep / ask | Typical fix |
| --- | --- | --- |
| **Phone-home / validator badges** | `grep -oE 'https?://[a-z0-9./-]+' <bundle> \| sort -u` — every external host in the bundle is a candidate. Does the UI *call* any of them by default (validators, "check for update", icon/badge CDNs)? | set the disabling key (`validatorUrl: null` and the like); assert it in a test |
| **Telemetry / analytics** | `analytics`, `telemetry`, `gtag`, `sentry`, `posthog`, `beacon`, `sendBeacon` | opt-out key, or strip via the vendor's build flag; never leave it on by default for tenant hosts |
| **CDN fallbacks and remote assets** | `unpkg`, `jsdelivr`, `cdnjs`, `fonts.googleapis`, `@import url(`, `sourceMappingURL`, `.woff` URLs | vendor the asset too, or confirm the reference is inert (a source-map comment fetched only with DevTools open is inert; an `@import` is not) |
| **"Try it" / proxy features** | any config that makes the UI fetch arbitrary user-typed URLs (`url` input bars, `urls[]`, "import spec from URL", request proxies) | pin to the same-origin resource; disable the URL bar layout; keep query-string config off (`queryConfigEnabled`-style flags) |
| **Auth surface** | does the shell embed a token, an example secret, or an example that copies a real config value? Does the UI persist entered credentials (`persistAuthorization`)? | never inline real values; persistence off unless deliberately on |
| **Deep-link / hash / query handling** | which parts of `location` the bundle reads and whether it escapes them (`deepLinking`, `layout` params) | keep the vendor's escaping path; don't add server-side interpolation to the shell |
| **License obligations** | the bundle's first line often names a `*.LICENSE.txt`; Apache-2.0 §4(d) needs `NOTICE` too | vendor `LICENSE` + `NOTICE` + the bundle's `LICENSE.txt` beside the files |
| **Pin integrity** | the sidecar `VERSION`/hash file vs the bundle's own embedded version string (`PACKAGE_VERSION:"x.y.z"` or similar) | a test that cross-checks the two — a half-done bump then fails in CI, not in a browser |

Two of those rows are worth automating once and forgetting: **"the shell references only
vendored files and sets the phone-home-off key"** and **"the sidecar hashes/version match the
bundle"** are both one small DB-free test each, and they turn the next bump into a green/red
signal instead of a re-review.

## Why the engine misses it

- The diff contains the *shell*, not the *behaviour*. A two-line minified bundle is skipped
  or summarised; its default branches are never in the reviewer's context.
- The shell reads as correct by construction — `url`, `dom_id`, two flags — so a diff-scoped
  reviewer has nothing to object to.
- The vendor's docs describe the opt-out keys, but nothing in the diff mentions them, so the
  reviewer has no cue to look them up.

The independent pass works because it is told to **open the bundle and the vendor config
reference**, not to re-read the diff.

## Hand-back wording

When this reference fired, say so in the review-loop hand-back: which probes ran, which
defaults were changed and which were accepted with a reason, and whether the two guard tests
exist. A shell with no test is a future regression on the next bump.
