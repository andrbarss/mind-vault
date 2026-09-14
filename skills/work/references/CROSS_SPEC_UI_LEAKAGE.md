# Cross-spec UI leakage — a floating artefact that outlives a spec breaks a sibling spec only under random order

Load when a green suite turns intermittently red after a new spec file is added, and the failing spec is
in a **different** file — especially a pointer-, geometry- or focus-driven spec (drag gestures, drop
positions, click-at-coordinates, `elementFromPoint`, focus traps). The new file is the suspect even
though the failure names another.

## The shape

An in-browser suite (Jasmine, Mocha, Karma, a Playwright-harvested page) shares one document across
every spec. Some UI side effects are **not owned by the component under test** and are not torn down
by the spec's `afterEach`:

- toasts / notifications / snackbars with an auto-hide timer (seconds, not ticks);
- modal masks and their `body` classes;
- floating menus, tooltips, drop-down pickers left expanded;
- global `wait` / progress boxes shown by a framework's action pipeline;
- scroll position, `document.activeElement`, a body-level `overflow: hidden`.

Each one lives past the spec that produced it. A later spec that computes **screen coordinates** or
reads **the element under a point** then sees a different page than the one it was written against.
Two toasts stacked in a corner were enough to move a drag-and-drop drop target by one row.

Two properties make this class expensive:

1. **Intermittent under random order.** Jasmine 3+ (and most runners) shuffle suite order by default.
   The leak only bites when the leaking file runs *before* the sensitive one, so a run passes, the next
   fails, and the failing spec looks flaky rather than broken. Fixed-order runs can hide it completely
   when the leaking file happens to be listed last.
2. **No single row reproduces it.** One artefact may be tolerated (a single toast off to the side); the
   leak needs two or more rows of the same kind — so a per-`it` bisect that runs each row alone stays
   green and reads as "not this file".

## Diagnosis that works

1. **A/B the suite with and without the new file**, several runs each. Build a throwaway copy of the
   harness page that omits the new file's `<script>` tag (or its include). 0/N without and > 0/N with
   is the whole signal — do not read the failing spec's own assertion text for the cause.
2. **Fix the order and put the suspect first.** Disable random order in the throwaway harness
   (`env.configure({random: false})` in Jasmine) and list the new file **before** the failing one. The
   failure should now be deterministic. If it is not, the leak is a timer that has not fired yet by the
   time the sensitive spec runs — widen the gap or stack more rows.
3. **Bisect by `describe`, then by `it`**, with `xdescribe` / `xit` on the rest, in the fixed-order
   harness. Expect the describe-level bisect to name one block and the it-level bisect to name
   *nothing* — that is the "two or more artefacts" signature. If one row reproduces it alone, it is a
   plain teardown bug, not this class.
4. **Name the artefact by reading the block's success path** — the call that produces something the
   component does not own (`toast(…)`, `MessageBox.wait(…)`, `Msg.show(…)`, a `focus()`, a
   `scrollIntoView`). The framework's own action pipeline is a common source: a form-submit helper
   that shows a wait box before the request, a success handler that toasts.

## The fix

- **Stub the artefact in the leaking spec's setup** (`spyOn(Ext, 'toast')`, `sinon.stub(notify,
  'show')`, a no-op `MessageBox`), and **turn the stub into a positive assertion** on the row whose
  behaviour includes it (`expect(toast).toHaveBeenCalled()`). Stubbing alone hides a regression where
  the success path stops toasting; the assertion keeps the row honest.
- Say **why** in the spec's header comment, naming the sibling it broke — the next author who reaches
  the same call will otherwise remove the stub as "unrelated".
- Where the sensitive spec is the one you own, make it robust too: reset scroll and clear masks in its
  `beforeEach`, and prefer coordinates derived at run time over constants.
- Do **not** fix it by pinning suite order. Random order is what surfaced the leak; a fixed order only
  moves it to the next file added.

## Anti-patterns

- ❌ Reading the failing spec's assertion (`[7,5]` vs `[5,7]`) as a bug in that spec's subject.
- ❌ Re-running until green and calling it flaky.
- ❌ Bisecting only by `it` in random order — every row passes alone, and the run order changes
  between attempts.
- ❌ Stubbing the artefact without asserting it fired.
- ❌ Disabling random order in the real harness to make the suite stable.
