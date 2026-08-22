# RULE_rename-before-drop — Rationale, Variants, Anti-Patterns

## Why This Matters

- **Bisectability.** Every intermediate commit compiles; `git bisect` works against post-merge regressions.
- **Test-pass between rename and drop is the safety gate.** Missed references surface as clean `AttributeError: 'X' object has no attribute 'old_name'` pointing exactly at the unswept site. Bundled with the drop, the same failure hides inside a multi-cause post-drop run. The canonical miss is a module-level `*_FIELDS` / `_COPY_*` constant in a file the surface-coverage matrix didn't enumerate — sequenced this way, 30+ tests fire on one cause; sequenced wrong, they hide in noise.
- **Post-drop re-test catches defensive fall-throughs.** Code shaped like `getattr(obj, 'old', default)` silently degrades when the old symbol vanishes — only the dedicated post-drop run forces it out.

## Two-PR Variant (Convention Migrations)

When the rename is a JS-level event-name / API-name convention rather than a schema field — e.g. many emit sites + many consumer modules — sequence as two PRs:

- **Phase 1 PR**: introduce the canonical helper; emit BOTH canonical AND legacy keys from every emit site (zero-risk overlap, legacy consumers unaffected); migrate consumers to the canonical signal. Phase 1 alone is functionally complete.
- **Phase 2 PR (later)**: drop legacy keys + remove legacy consumer listeners. Reversible if Phase 2 surfaces a regression.

The test-pass between phases is the safety gate that surfaces asymmetries (e.g. helper emitting on success path only, never on failure path — caught cleanly when isolated, hides inside a drop-bundled diff).

## Forced-atomic member: module → package collision (flat → package refactor)

A flat→package split (`app/x.py` → `app/x/`) has one rename member that can't keep a drop-later
shim: a module and a package can't share a dotted name, so the colliding name is *forced atomic* —
bridged transparently by the package `__init__` re-export instead of a shim, while the *other*
absorbed flat modules ride normal one-commit shims. Full mechanics + mixed-bridge sequencing live
in the (Python-general) module-split reference:
[`skills/django/references/MODULE_SPLIT_AST_EXTRACTION.md`](../../skills/django/references/MODULE_SPLIT_AST_EXTRACTION.md)
§ *Sequencing — the forced-atomic member*.

## The bridge state must be writable — relax the legacy column's NOT NULL in step 2

The pattern assumes that between "add new" (step 2) and "drop old" (step N+2) the codebase can
run with writers populating only the new symbol. For a column rename that is only true if the
old column accepts rows that don't set it. Field case: `users.name NOT NULL` → `first_name` /
`last_name`. Migration 1 added the new columns and copied the data; the model, factory and
seeder switched to the new pair (step 3); the full test pass then failed on every factory
insert with `NOT NULL constraint failed: users.name` — the old column was still mandatory and
nobody wrote it any more. The only ways out were (a) keep writing a derived `name` until the
drop (a phantom writer that the drop commit must also remove — the big-bang coupling the rule
exists to prevent) or (b) the fix: amend migration 1 to `->nullable()->change()` the legacy
column, with `down()` refilling it and restoring `NOT NULL`. Do (b) up front, in the
add-columns migration: the bridge state is then genuinely writable, every intermediate commit
is green, and the drop migration stays a pure `dropColumn`. Same logic for a `UNIQUE` that the
new columns now carry, or a `CHECK` the old value can no longer satisfy. A DB-level migration
test that rolls back to the legacy schema, inserts old-shape rows, migrates forward, and
inserts a *new-shape* row (old column omitted) pins the bridge state — the model-level suite
can't, because `RefreshDatabase` starts fully migrated.

## Anti-Patterns

- ❌ Leave the legacy column `NOT NULL` through the bridge — step-3 writers fail, and the "fix" drifts toward bundling the drop.

- ❌ Big-bang rename + drop in one commit — bisectability dies, regressions become undifferentiated noise.
- ❌ Drop first, then rename references — every intermediate commit is broken; tests can't run.
- ❌ Skip the post-drop re-test because the rename pass was green — defensive `getattr` fall-throughs hide here.
- ❌ Append the drop to the same Django migration as the data migration — couples data + schema steps in development; separate `0NNN_drop_legacy_*.py` is cleaner for review.

## Relationship To Other Rules

- [`RULE_git-safety`](../../rules/RULE_git-safety.md) — every rename and drop commit lands on a feature branch; per-commit compilability makes `--force-with-lease` rebases safe inside the sequence.
- [`RULE_self-sweep-before-push`](../../rules/RULE_self-sweep-before-push.md) — pyflakes after a rename catches leftover imports of the dropped symbol.
