# Plan-stage schema contract — the DDL hand-off that unblocks a parallel consumer

Load when a plan's schema change will be consumed by work in **another codebase or by another team / agent swarm** — an admin-UI write-side, a sibling service, a client generator — that would otherwise sit blocked until `/work` ships, or worse, build against a guessed schema. Field-proven twice: once to freeze a deferred write-side's writer invariants so a later CRUD IDEA could be planned against them, and once to hand a display-slot column set to a parallel UI team the same day the plan locked.

## The pattern

`/plan` emits a standalone **`schema-contract.md`** into the idea's archive dir *alongside the plan, before `/work` starts*. The plan lists it as a plan-time deliverable; the implementing migration later **mirrors it verbatim** (divergence between contract and migration is a review finding, not a judgement call).

The contract carries five sections:

1. **The model** — a compact semantic table: column → meaning → who writes it → who reads it. One paragraph of narrative on what a row *is* under the new shape. **Say what NULL means.** A nullable column is either a *bridge state* (relax-then-tighten: NULL is a gap awaiting a backfill and `NOT NULL` is the planned final shape) or a *meaningful value* (NULL is the normal case — "no special handling", "not curated" — and the column is final as-is). The two read identically in DDL and lead consumers to opposite designs: a bridge makes the client treat null as transient and the writer plan a backfill; a meaningful null makes null the default branch and a value the exception. The relax-then-tighten sequencing rule biases authors toward reading every nullable column as a bridge — field-caught when a plan drafted "tighten to NOT NULL in a later contract version" for a marker column the product owner meant to stay optional forever. State which one in the model paragraph, and if it is a bridge, name the backfill owner.
2. **UP DDL and DOWN DDL, exact** — copy-paste SQL, not prose. State the backward-compatibility rule the DDL encodes (e.g. which `DEFAULT` makes every pre-existing row keep its current behaviour with zero backfill) and what the DOWN destroys (curation data, orphaned semantics) so the rollback cost is agreed in advance.
3. **Writer invariants the DB cannot enforce** — numbered, one per line. Two disciplines here:
   - **Composability check**: read every pair of invariants as a naive consumer would. Two individually-true rules can read as contradictory ("full delete+reinsert is legal" vs "never delete a row to remove one membership") — when they can, add an explicit composition sentence ("X is legal **iff** Y") rather than trusting the reader to reconcile them. Field-caught by an architect pass: the contract locks at plan time, so a wording ambiguity ships to the consuming team and surfaces as a wrong write-side months later.
   - **Reader-tolerance declarations**: state what readers IGNORE ("a slot's position is ignored while its flag is 0"), because that is what makes a lazy writer harmless and tells the consumer which cleanup writes it may skip.
   - **Order the rules as the save pipeline when order changes the outcome.** Validation invariants are applied by the consumer *in the order written*, and a numbered list reads as a sequence. "Format must match `^[a-z0-9]…$`" listed before "empty input is stored as NULL" makes an implementer reject an emptied field instead of clearing it — the exact `''`-vs-NULL hazard the second rule exists to prevent (a second `''` then violates the unique key). Write the pipeline explicitly — trim → empty ⇒ NULL and *stop* → normalise → format → uniqueness (pre-check for the friendly message, then catch the duplicate-key error as the guarantee) — and say which steps a short-circuit skips. Architect-caught on the same contract as the composability check above: two individually-correct rules, wrong in that order.
   - **"Blank ⇒ NULL" on a numeric column: spell the test as `=== ''`, never "empty".** A pipeline written as "trim → empty ⇒ NULL" reads as PHP `empty()` / JS `!value` to the implementer — and both are true for `'0'`, so a legitimate position / rank / weight of `0` is silently stored as NULL, contradicting the "any integer is legal" invariant two lines below. Write the numeric pipeline in full: type guard first (an integer passes; a string continues; anything else → 400 — `trim()` on an array is a TypeError → 500) → `trim` → `=== ''` ⇒ NULL and *stop* → `^-?\d+$` else 400 → signed-INT range else 400 (strict-mode MySQL answers 1264 out-of-range, which surfaces as a 500) → store as int. Architect-caught on an ordering-column contract: the two rules were individually correct and jointly wrong for exactly one input.
4. **What the reading side will expose** — the response fields the consumer's data will surface, so the writer team sees the round trip, not just the tables.
5. **A seed / probe example with expected output arithmetic** — concrete INSERTs plus the exact derived result ("rows so-configured ⇒ list A = [1,2], list B = [3,1], list C = [2]"). This one section does triple duty: the architect pass can verify the arithmetic against the model, the implementing side's live verification curls it as its acceptance check, and the consuming side can seed the same rows and assert its UI. If the two codebases ever disagree, the seed example is the arbitration record.
   - **The seed must be able to *discriminate* the rule under test.** A probe row whose expected output is the same under every candidate rule proves "nothing regressed", not the rule. The trap is *co-monotonic* fixture data: when the new ordering column, the foreign key, the primary key and the physical insertion order all agree (the smaller key always sits on the smaller id — the normal shape of rows that were inserted in sequence), "order by key", "order by id" and "no ORDER BY at all" return identical rows, so the all-NULL and equal-position rows of an order-by contract verify nothing about the tie-break they claim to verify. Either break the coincidence on purpose (one reversible `UPDATE … CASE` that swaps two rows' foreign keys, restored afterwards) and expect the *different* order, or label those rows as no-regression rows and cite the DB-free pin as the actual evidence for the rule. Ask of every seed row: *which candidate rule would make this row come out differently?* If the answer is "none", the row is decoration. Architect-caught on a plan whose five verification rows all agreed under three different orderings.
   - **Every acceptance row must be producible by the client your own contract shapes.** A UI contract that specifies a client-side guard in one section (`maxLength: N` on the field) and, two sections later, an acceptance row that expects the *server's* over-length message for the same input has written a row the form cannot reach: the framework fails `isValid()` before any request is issued, and what the clerk sees is the field's own marker plus a generic dialog. Field-caught by the consumer's note, after the contract shipped. Per row, name the signal and ask which side produces it; when a client-side rule short-circuits the server's, split the row — the client gets "N+1 ⇒ field invalid and **zero** requests, N ⇒ one request" (a request spy makes the zero-requests clause the discriminating part), and the server's refusal goes into *your* suite (a fake upstream answering the exact refusal body, asserted byte-identical) and the owner's walk. The consumer-side mirror of this rule is `CONTRACT_CONSUMER_DISCIPLINE.md` § 5.

## Why plan-time, not work-time

- The consumer starts immediately — schema debates (naming, discriminator-vs-flag shape, per-list ordering) happen once, in the plan's architect review, instead of after two codebases built against different guesses.
- The contract is small enough to review exhaustively at plan time; the migration that mirrors it later needs only a "matches the contract verbatim" check.
- Locking the DDL early is safe *because* the contract is additive-biased: when the design demands additive columns with behaviour-preserving defaults (see the architect PASS 4 additive-columns bullet for the read-path consequences), a later plan revision is a new contract version, not a silent drift.

## When the shipped behaviour departs from the requesting contract

The contract flows both ways. When *this* repo is the one asked for a column (the consumer wrote the request — DDL plus the rules it expects the reader to honour), the migration still mirrors the DDL verbatim, but the **reader rules are this repo's decision** and can legitimately end up different from what the request assumed. Field case: a requesting contract for a retire flag said "the storefront must keep emitting values of retired attributes"; after the first review the owner decided the storefront hides them. Two things then have to happen, and neither is a silent edit:

1. **This repo's mirror contract states the departure explicitly** — a one-line "differs from the requesting contract's § X, decided YYYY-MM-DD" at the top and the replacement rule in the affected section — so an agent reading both files sees a deliberate divergence, not a drift to reconcile back toward the request.
2. **The requesting contract is amended in the *other* repo** — but that file usually lives on that repo's own in-flight branch, with an uncommitted tree the amending session does not own. Do not edit it from a docs pass of this repo. Ship a **paste-ready hand-off**: the exact replacement bullet(s), the model-table cell wording and a Provenance line, in this IDEA's archive README (the wrap's canonical landing page), and name it as an owed item in the devlog and the hand-back. The human (or the other repo's next `/plan`) applies it.

Also **split the ALTER honestly**: when one requested `ALTER` lands as two stems on this side (the first column shipped before the second was planned, and applied migration files are content-hashed — never re-opened), the mirror contract records both stems, the identical end state, and the one rollback-topology difference (both pending ⇒ one batch ⇒ a bare `rollback` reverts both; otherwise `--migration=<stem>`), so the consumer's degrade table still maps one-to-one.

## Writing the *requesting* contract — when the table's owner has not planned yet

The section above covers the owner receiving a request. The other direction comes up when your
repo is the **writer** of a table another repo will own, and the owner has only *captured* its
idea. Waiting blocks both teams; guessing their DDL builds your fixture on sand. Write the request:

- **Author the DDL you need as a requesting contract** — the same five sections, a banner that
  names the direction ("requesting; the owner's contract governs once it exists"), and an *owed*
  list the owner's `/plan` can adopt item by item. Field case: the owner adopted the DDL unchanged
  except an optional `CHECK` — dropped because servers below MySQL 8.0.16 parse and ignore it, and a
  constraint that holds on some tenants and not others is a false guarantee (the rule stayed
  writer-owned).
- **"Not planned yet" is a fact about the owner's branch *right now* — re-read it immediately before
  you emit, not at session start.** The owner's `/plan` can run in the same hour as yours. Field
  case: the owner's contract landed on its branch seven minutes *before* the requesting draft was
  written; the requesting `/plan` had checked the branch at session start, wrote a `VARCHAR(32)`
  request, and only the architect's re-read found the owner's `VARCHAR(64)` file — every plan
  section, both contracts and the fixture's length then changed. The check is one command on the
  sibling checkout — `git fetch origin && git log -1 --format='%H %ci' origin/<branch> --
  docs/archive/<idea-dir>/schema-contract.md` — run as the last thing before writing the banner.
- **Gate the scaffolding commit on a re-read at `/work` start.** If the owner has emitted theirs by
  then, mirror it verbatim *before* building the fixture and drift guard, and conform to it.
- **The owner planning first does not end the moving target.** A contract on a draft PR keeps
  moving through the owner's own `/work` and verification (field case: three revisions after the
  plan, all prose — an engine note, a third channel's error shape, a verification line). Re-read
  at `/plan`-emit, `/work` start, `/work` end **and `/wrap`**; the banner's per-revision change list
  is what tells the next reader "DDL, invariants and the hand-off never moved" without a diff.
- **Mirror every revision until the owner merges.** Body byte-identical; the banner carries the
  source commit, the md5 of the body, and a change list across mirrors. The owner's file can move
  several times — plan, architect review, PR review, wrap (field case: four mirrors in one day,
  every change reader-side).
- **Make the mirror checkable by the suite.** The drift guard parses the UP statement *out of the
  mirrored markdown* (comments and whitespace stripped) and compares it with the fixture's DDL, and
  a second test re-hashes the body after the banner's separator against the banner's md5 — so an
  in-place edit of the mirror, or a fixture that drifts from it, goes red. The guard cannot see the
  owner's repo moving: re-read at the end of `/work` and at `/wrap`.
  **Write the banner in the guard's shape, and compute the hash with the guard's own slicing.** A
  copied guard does `preg_match('/md5 ([0-9a-f]{32})/')` and hashes everything after the first
  `"\n---\n\n"`. A banner that reads "md5 of the body below the rule:" with the hash on the next
  line fails the regex before it ever compares, and a hash computed over "the file I pasted" is
  not the hash of the sliced body — field case: both, on one requesting banner, caught by the
  architect before the first suite run. Put `md5 <hash>` on one line, produce the hash by running
  the guard's slice (a one-liner through the project's own runtime), then run the guard once
  before committing the mirror.
- **Corrections flow back as paste-ready text in the banner** (for example, a lock claim measured
  false); the owner adopting one closes it, and the next mirror's change list records the closure.

## Read the consumer's note before emitting the build contract

A parallel consumer's `/plan` can run first and write down what it needs from *your* contract — a
note file in its own archive directory, on its feature branch — before your `/plan` exists.

- **Before emitting, look for it**: list the sibling repo's branches for your idea and grep their
  trees, e.g. `git -C <sibling> ls-tree -r --name-only origin/<branch> | grep -i note`. Field case:
  the note was found at the end of `/work` and cost a reshape commit.
- **When the consumer seeds editable state from the record, do not also emit that state from the
  reference list.** A server-computed `checked` flag on a picker is a second source of the same
  selection, and it invites building the write payload from the list store — which is empty before
  it loads, so the save sends `[]` and wipes the set. Emit the list without selection; the record
  carries the selection. (The consumer side of the same trap: `CONTRACT_CONSUMER_DISCIPLINE.md` § 1; how the consumer writes the note and asks for a list route that doubles as a provisioning probe: § 8.)
- **A change after the consumer's re-read owes a delta note.** When your review cycle amends the
  contract after the consumer verified it, write each change and whether it needs consumer code as
  paste-ready text in your archive.

## Charset and collation are part of the DDL — pin them on `ADD COLUMN` against a legacy table

A column added with `ALTER TABLE … ADD COLUMN x VARCHAR(100) NULL` takes the **table's** default character set — not the database's, not the neighbouring columns'. On a schema that grew up before utf8 (MySQL `latin1` defaults are the common case), a table can default to latin1 while every one of its text columns carries its own `CHARACTER SET utf8mb4 COLLATE …` — readable, and a trap: the next additive column silently lands as latin1, and every non-Latin-1 letter is mangled **on write**, under HTTP 200, on every tenant. Nothing in a DB-free suite can see it; the migration round trip is clean; only real data exposes it. Field case: an eight-locale display-name family shipped latin1 on the first cut and stored `Š` as one byte; the seed read-back caught it before the first push.

Three disciplines, in order:

1. **Read the table default before writing the DDL** — `SELECT TABLE_COLLATION FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '<table>'` plus the `CHARACTER_SET_NAME` of two existing text columns. A dump in which every text column spells its own `CHARACTER SET` is the tell that the default is something else. If the default is not the charset you want, **every new text column in the contract's UP DDL pins `CHARACTER SET … COLLATE …` explicitly**, matching the table's newest text columns, and the migration header says why (so a later "tidy-up" does not drop it).
2. **The contract under-specifies without it.** `VARCHAR(100) NULL` is not a complete column definition on such a schema; the consumer building a form against the contract will validate length in characters that the column then cannot store. Treat charset/collation as part of the frozen DDL, like the type and the nullability.
3. **The seed probe is the acceptance gate for the bytes, not just the arithmetic.** Seed at least one value with a non-ASCII letter and read back `HEX(col), CHAR_LENGTH(col), LENGTH(col)`: the bytes must be the UTF-8 sequence and `LENGTH > CHAR_LENGTH`. Run it before the first push, while rolling the stem back still costs nothing — a stem that has reached a tenant is content-hashed and gets a *second* migration instead of an edit. (Seed from a client set to utf8mb4; a latin1 *client* produces a different, double-encoded symptom that looks like the same bug.)

## A per-pair setting stored on per-child rows — invariant, tolerance, and a two-direction probe

A setting that is *one fact per (parent, item) pair* sometimes has no row of its own: the only
table that carries the pair is a **child** table with N rows per pair (one row per selected
option, per translation, per line). Display placements on a per-parent attachment whose values
are multi-row is the field case: three boolean flags that mean "this attribute shows on the
card for this room type" had to live on the values rows, N of them for a multi-select
attribute. The contract then owes three things, and each of them is a distinct section:

1. **Writer invariant — every row of the pair carries identical values.** The consumer's save
   path (typically delete-all + reinsert per pair) writes the N rows from *one* form state;
   "never update one row of a pair and leave the others". Say it as a numbered invariant, and
   say that the reinsert must carry the columns on every row (a reinsert that omits them
   silently resets the setting to the DDL defaults on every save — the same footgun as any
   additive column on a delete-all + reinsert path).
2. **Reader tolerance — which row is authoritative when they disagree.** Pick a deterministic
   row and state it in the contract so both codebases read the same thing on a drifted pair.
   The rule that survived review: **the first row the reader actually emits** — first by the
   existing sort, *after* the reader's own validity filter (a dropped row's values never count).
   Two rules are tempting and wrong: OR across rows (the setting then depends on which row a
   lazy writer happened to touch) and drop-on-disagreement (harmless drift becomes a vanished
   item on the public surface). One implementation trap goes with it: shapers often capture a
   "head" row *before* sorting for the fields that are identical on every row; the first
   per-row field that is *not* identical must be read from the post-sort, post-filter survivor,
   never from that head.
3. **A seed probe that discriminates the rule.** Clearing the setting on a *later* row and
   seeing the item still present proves nothing — first-wins, OR-across-rows and OR-across-emitted
   all answer the same. The only direction that separates first-wins from an OR is **clearing
   the first row while setting a later one** and expecting the item *absent*. Put both
   directions in the contract's seed section so the consumer's tests assert the same
   arithmetic; and in the reader's unit fixtures put the row whose value must be *ignored* at
   input index 0 with the lower sort key, so a head-based implementation fails the test.

The absence of a per-pair row is also why "per-pair ordering" should be resisted here: an order
column would have to be replicated across the N rows with the same disagreement problem, for an
order the parent catalogue usually already provides. Say so in the contract's model section so
the consumer does not invent one.

## Adding a second reader to a contract another repo mirrors

A contract that says "the only place this table is read" stops being true the day a listing, a report
or a sync job reads it too — and if the consumer mirrors the file verbatim with a checksum banner,
every stale sentence is now *their* stale sentence. The new reader is a **revision of the contract**,
not a footnote. Walk the file for every claim the first reader's exclusivity made true, and amend
each with a dated marker:

- the audience / provenance banner ("read by …");
- any departure that reasoned from the first reader's order ("the reader refuses X *before*
  consulting the table" — a listing with no requested target reads the table *first* and applies X
  per row);
- the model table's "Read by" cell (one statement per request of *either* reader; say whether a
  per-request memo exists and that it is not a cross-request cache);
- the reader-rules section: the second reader's own gates, in the shared order, what it answers
  when the entity-level gates refuse (and which rows never read the table at all — an entity with no
  key), its only 400, its 500 rule;
- the seed / probe table: at least one row only the second reader discriminates (a self-referencing
  row it must omit; the accepted set in ascending key order) — and re-read the existing rows'
  letters against the walk mapping, because "`[B, C]` ascending" is false the moment C < B;
- the rollback / degrade line (which requests the missing table now breaks);
- the hand-off list: retire any "no companion reader ships" item, and add an **open re-mirror item**
  stating "reader-side only — no DDL, writer-invariant or cache change" so the consumer knows the
  scope of what it copies.

A reviewer that mirrors the file will flag every sentence you missed, one round later; the cheap
version is the walk above at `/plan`, with the exact section list in the commit trailer and the
amending IDEA's backref.

## Anti-patterns

- ❌ Reconciling a deliberate reader-rule departure *back* toward the requesting contract because "the contract says so" — the request describes what the consumer assumed, not what the owner of the reader decided; check the mirror contract's departure note first.
- ❌ Handing the consumer the plan document itself — plans carry execution sequences, open questions and repo-relative paths that mean nothing in the other codebase; the contract is the extracted, stable subset.
- ❌ A contract without the DOWN DDL — the consumer needs to know what a rollback window does to their writes.
- ❌ A seed example without expected output — un-checkable, so it decays into decoration.
- ❌ A seed row whose expected output is identical under every candidate rule — it passes for the wrong reason (co-monotonic fixture data); swap two keys or label it no-regression.
- ❌ A disagreement probe that only clears a *later* child row — every candidate tolerance rule answers it the same; clear the *first* row and set a later one, expecting absence.
- ❌ "Empty input ⇒ NULL" on a numeric column without saying `=== ''` — `empty('0')` erases a legitimate zero.
- ❌ `ADD COLUMN … VARCHAR(n)` with no `CHARACTER SET` against a table whose default you have not read — on a pre-utf8 schema the column lands latin1 and mangles text on write; the round trip and the DB-free suite stay green.
- ❌ Writing the migration first and extracting the contract after — the review order inverts, and the consumer's blocked window extends through /work.
- ❌ Building the fixture from your *requesting* contract after the owner has emitted theirs.
- ❌ A mirror whose body can be edited in place without a failing test.
- ❌ A picker that ships its own selection flag next to a record that already carries the selection.
- ❌ A second reader added with a paragraph in its own docs but no revision of the mirrored contract — the consumer copies "the only place this table is read" as still true.
- ❌ Emitting a *requesting* contract on a "the owner has only captured" claim verified at session start — the owner's `/plan` can land in the same hour; re-read the owner's branch as the last step before writing the banner.
- ❌ A mirror banner the copied guard cannot parse — the md5 phrase split across lines, or a hash computed over anything but the guard's own slice of the body.
- ❌ An acceptance row that expects the server's message for an input your own contract told the client to refuse first — unreachable from that form; give the client a zero-requests row and pin the server refusal in your suite.
