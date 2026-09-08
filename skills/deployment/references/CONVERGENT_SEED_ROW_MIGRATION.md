# Seeding a row a UI can also create — a guarded INSERT is idempotent by SKIP, not convergent

Load when a migration **seeds a row into a table that an application UI can also write** — a settings / theme-property / feature-flag / lookup registry, anything where an operator can hand-create the same logical row from a form. The guarded-insert idiom that makes such a migration safely re-runnable is **also** what makes it permanently unable to repair a row that got there first.

Sibling to [`MIGRATION_STATEMENT_ORDERING.md`](MIGRATION_STATEMENT_ORDERING.md): that one is about surviving a *mid-file* failure (statement order); this one is about surviving a *second writer* (row provenance). Both apply to the same file.

## The failure

The idiom:

```sql
INSERT INTO `settings` (`key`, `value`, `widget_type`, `choices`, `description`)
SELECT 'feature.x', '0', 'string', '[["0","Off"],["1","On"]]', 'What it does'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM `settings` WHERE `key` = 'feature.x');
```

Re-running is safe. That is idempotence **by skip** — the second run does nothing *because the name already exists*, not because the row is correct.

Now the ordinary sequence for a two-repo change: the reader deploys before the fleet migrates. An operator wants the flag, finds it missing, and creates it from the admin form. Application create-paths rarely produce the same row a migration does:

- the form's *new-row* branch often renders a different widget (a free-text field instead of the choice control), so **`choices` lands NULL**;
- create-paths frequently stamp provenance — `is_custom = 1`, `created_by`, `source = 'manual'` — that the migration's INSERT never sets, taking the column default instead;
- optional prose columns (`description`, `help_text`) are simply absent from the quick-create form.

Then the migration runs. It sees the name. **It skips — permanently.** That tenant keeps a malformed row forever, and under a checksumming runner the applied file may never be edited to repair it. The only remedy left is a second migration written by hand later, if anyone notices.

The bug is invisible in review: the up-file reads as textbook-correct, and every test on a *fresh* database passes.

## The rule

**Pair every guarded seed INSERT with an idempotent repair `UPDATE` in the same file.** The INSERT seeds a fresh DB; the UPDATE converges a DB where something got there first. Both are idempotent, so the ordering rule in the sibling reference stays satisfied (there is no unguardable statement to order against).

```sql
UPDATE `settings`
   SET `widget_type`  = 'string',
       `choices`      = '[["0","Off"],["1","On"]]',
       `is_custom`    = 0,
       `description`  = IF(`description` IS NULL OR `description` = '',
                           'What it does', `description`)
 WHERE `key` = 'feature.x'
   AND (`widget_type` <> 'string'
        OR `choices` IS NULL OR `choices` = ''
        OR `is_custom` <> 0
        OR `description` IS NULL OR `description` = '');
```

Three things make this correct rather than merely present:

### 1. Enumerate the shape columns by asking what a consumer *branches on*

Not "which columns did the INSERT list". The question is: **which columns does downstream code make a decision on?** Those are the shape columns, and every one of them must be in both the `SET` and the `WHERE`.

The field case that produced this reference: the repair covered the choice list, the provenance flag and the description — and missed the **widget-type discriminator**. It was the one column that decided which control the form rendered, so a row created from the wrong menu entry could *never* display the intended control. Worse, the repair's own provenance normalisation (`is_custom = 0`) then made the row **undeletable** through the UI (the delete path refuses non-custom rows) and the key field non-editable — so the operator could no longer delete-and-recreate their way out either. The repair had closed the last escape hatch while leaving the defect in place.

A cheap way to find the set: grep the consuming UI for every `if (row.<column>` / `switch (row.<column>` and take the union.

### 2. Repair shape, never intent

The operator's **value is theirs** — never overwrite it. If they set the flag on, it stays on; the migration is fixing *how the row is shaped*, not *what it was set to*. The same applies to prose they authored: fill `description` only when NULL/empty (the `IF(...)` above), so a hand-written note survives.

Keep the guard expression and the `SET` expression **identical** for any column that is conditionally written, so the two can never disagree. (Watch collation here: on a PAD SPACE collation `'   ' = ''` is TRUE, so a whitespace-only value is treated as empty by *both* — consistent, and usually what you want.)

### 3. Say what the DOWN file does about rows it did not create

The down file deletes by name, so it also removes an operator-created row. That is usually the right call — guarding on ownership (`AND is_custom = 0`) strands orphan rows after a rollback, which is worse — but it is a real asymmetry and belongs in the file header, not in someone's memory.

## Verification — the case that actually matters

A fresh-DB test proves nothing about this. The discriminating case is:

1. Insert a **deliberately malformed** row the way the UI would: right name, wrong widget type, NULL choices, provenance flag set, no description, and a non-default `value`.
2. Run the up-file.
3. Assert **every** shape column is canonical, the **`value` is unchanged**, and there is still exactly **one** row.
4. Re-run with an operator-authored `description` in place and the shape broken again; assert the shape repairs and **their text is untouched**.
5. Re-run on the now-canonical row; assert the UPDATE matches nothing.

## Also worth knowing

**No UNIQUE key means "exactly one row" is an assumption, not a guarantee.** These registry tables are often `PRIMARY KEY (id)` only. If duplicates of the name exist, the guarded INSERT still adds none and the repair normalises the shape of *all* of them — but their `value`s stay independent, and a reader that folds the table into a map (`array_combine`-style) silently keeps whichever the engine returned last. State this in the file header; do not "fix" it by deleting rows, which is operator data.

**A seeded row can surface on endpoints that never name it.** See [`../../plan/references/WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md`](../../plan/references/WHOLESALE_EMITTERS_DEFEAT_NEGATIVE_GREPS.md) — a `SELECT *`-and-dump endpoint publishes the new row the moment the migration runs, with no code change, which also means "nothing reads this row" cannot be established by grepping its name.
