# Forced dark mode — declaring a light-only page in code, pinning it, and proving it

Load when a page must **always render light** (a guest-facing key / ticket / PIN page, a print-like
document, a page whose brand palette has no dark variant) and the failure being prevented is a browser
that darkens pages on its own: Chrome Android "Auto Dark Mode for Web Contents", Samsung Internet
"Dark mode for web content", Xiaomi / Opera dark modes, and Chrome Desktop behind
`chrome://flags/#enable-force-dark`. Those browsers invert whatever the page did **not** declare: an
undeclared white body goes black, an explicit black button stays black, black text stays black — the
user gets black-on-black exactly where the page matters most.

A real dark theme is a **separate design** (see `BASE_TEMPLATE.md` / `ADVANCED_COMPONENTS.md` for the
theme-toggle pattern). This reference is the opposite decision: opt the page *out* of every browser
darkening, in code, so the outcome never depends on the device.

## 1. The guard — seven declarations, all of them

```html
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="only light">        <!-- 1 -->
  <style>
    :root { color-scheme: light; color-scheme: only light; }  /* 2 — both, in this order */
    html, body { background: #ffffff; color: #111827; }       /* 3 */
    input, select, textarea { background: #ffffff; color: #111827; }
    .btn-primary { background: #000000 !important; color: #ffffff; border-color: #000000; } /* 4 */
    .card, .panel { background: #ffffff; color: #111827; }
    /* … every primary element: explicit background AND text colour, 6-digit hex … */
    @media (prefers-color-scheme: dark) {                      /* 5 — last */
      html, body { background: #ffffff !important; color: #111827 !important; }
    }
  </style>
</head>
```

1. **`<meta name="color-scheme" content="only light">`** — the page-level declaration the auto-dark
   heuristics read first. `only` is the spelling that opts out of forced darkening; a bare `light` only
   states a preference.
2. **`color-scheme` twice in `:root`, `light` first, `only light` second.** Engines that do not parse
   `only` drop the second declaration and keep the first; engines that do parse it take the second.
   Order matters — the cascade keeps the *last valid* declaration.
3. **Explicit `html, body` background and text colour.** The inversion targets undeclared surfaces;
   declared ones are left alone (or, in forced-dark engines, treated as "the author meant it").
4. **Every primary UI element declares both colours, in 6-digit hex.** Buttons, outline buttons, icon
   buttons, cards / panels, inputs, the page's own chrome (a language pill, a header band). In *value
   position* on those rules: no `inherit`, `transparent`, `initial`, named colours (`white`, `black`)
   or CSS variables — each of those is a hole the heuristic fills with its own guess. (`transparent`
   as a *border* colour, or `initial-scale` in the viewport meta, are not value-position colours; a
   naive grep over-matches — scope the check to the audited rules, § 2.)
5. **A `@media (prefers-color-scheme: dark)` block that re-asserts `html, body` with `!important`**,
   last in the stylesheet, for user-agent stylesheets that switch their defaults on the OS preference.
6. **`<html lang="…">`** — not a colour rule, but the same audit usually finds it missing; forced-dark
   heuristics and screen readers both key off it.
7. **Nothing dark-themed elsewhere.** A page can carry the guard and still be broken by a shared
   stylesheet loaded after it; the audit covers the whole cascade the page actually loads.

## 2. Pin it — a static-source test over the template

The guard is cheap to lose in a "tidy-up" of the stylesheet, and no behavioural test sees colours. Pin
the *source*: read the template file in the unit suite, strip `/* … */` comments, and assert:

- the meta tag literal, and both `color-scheme` declarations inside the `:root` rule with `light` before
  `only light`;
- the `prefers-color-scheme: dark` block containing both `!important` declarations;
- for each audited selector list, a **rule-scoped extractor** — `^\s*<exact selector list>\s*\{([^}]*)\}`
  with the multiline flag (rule bodies never nest, so `[^}]*` is exact; `@media` inner rules are matched
  the same way) — then, inside the captured body: positive per-declaration pins
  (`/background:\s*#ffffff\b/`, `/color:\s*#111827\b/`, or the button pair) and negative value-position
  pins `/:\s*(inherit|transparent|initial|black|white)\b/` and `/var\(/`.

Rule-scoping is what makes the negative pins honest: a whole-file grep for `transparent` fails on the
spinner's `border: 4px solid transparent`, which is not a colour hole.

## 3. Prove it — emulate both dark conditions before asking for real devices

Two different things darken a page, and they are emulated differently. Both are available from
Playwright against Chromium:

```js
const cdp = await page.context().newCDPSession(page);
await cdp.send('Emulation.setAutoDarkModeOverride', { enabled: true }); // forced / auto dark
await page.emulateMedia({ colorScheme: 'dark' });                       // OS preference
await page.goto(url, { waitUntil: 'networkidle' });                     // FRESH navigation — see trap 1
await page.screenshot({ path: 'room-forced-dark.png' });
```

`Emulation.setAutoDarkModeOverride` is the same switch as DevTools → Rendering → *Enable automatic
dark mode*; a human reproduces it there, or with the Chrome flag.

Three traps, each of which produced a wrong answer once:

1. **The override is applied at navigation time.** Enable it and then `page.setContent(...)` (or
   inspect the already-loaded page) and *nothing* inverts — an unguarded page "passes". Enable first,
   then `goto` / `reload`.
2. **Computed styles never change under forced dark.** Chromium inverts at paint time;
   `getComputedStyle(body).backgroundColor` reports the authored white in every state. Only screenshots
   are evidence for the forced-dark column.
3. **Run an unguarded control page in the same session.** A white `data:` page with no
   `color-scheme` must come back near-black under the override; if it does not, the emulation is not
   live and the guarded page's "still white" proves nothing.

What emulation cannot do: Safari iOS and Firefox have **no** forced-dark feature (their rows are Light /
Dark only), Samsung Internet's darkening is its own implementation, and vendor Android browsers differ.
A real-device matrix is still the acceptance evidence — record the emulated rows as *emulated*, never
as ✅ real, and treat the matrix as a human-only criterion whose close-out gate is decided at plan time
(`../../wrap/references/IDEA_COMPLETENESS_AUDIT.md` § Human-only acceptance criteria).

## Anti-patterns

- ❌ `<meta name="color-scheme" content="light">` alone — a preference, not an opt-out.
- ❌ `color-scheme: only light` as the *only* declaration — engines without `only` support ignore it
  and fall back to the UA default.
- ❌ Colours via `var(--bg)` on the guarded rules — the variable resolves after the heuristic has decided.
- ❌ Verifying with `getComputedStyle`, or with `setContent` after enabling the override — both are false
  negatives (§ 3).
- ❌ Marking the device matrix ✅ from emulation.
