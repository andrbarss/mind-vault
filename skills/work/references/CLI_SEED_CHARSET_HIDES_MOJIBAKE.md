# Seeding UTF-8 text through a DB CLI without a charset double-encodes it — and the same session's read-back hides it

Load when a verification walk seeds names, descriptions or any non-ASCII text on a dev clone through
the database CLI (`mysql`, `psql`, `docker compose exec … mysql -e "…"`) and then captures an API
response that carries that text.

## What happens

A `mysql` client started without `--default-character-set=utf8mb4` (the default in the official
container image is `latin1` for the *client* side) sends the bytes of `ų` (`C5 B3`) as two latin1
characters; the server transcodes each into utf8mb4 and stores four bytes. The row now holds
`Å³` — and every HTTP response that reads it carries `Å³`. But a `SELECT` through the **same** CLI
session runs the conversion backwards and prints `ų`, so the read-back you use to "verify the seed"
shows exactly what you typed. The capture committed to the archive and the verification guide's
transcript disagree, and the guide is the one that is wrong.

The field case: a throwaway parent row seeded with a `[amount]` placeholder in its Lithuanian name.
The CLI read-back, the guide and the coupon rows all *looked* right; the committed listing capture and
`getcouponinfo` on the wire carried `Å³`. A convention reviewer caught it by comparing the capture
against the guide's quoted text — a sibling row seeded through the admin form read correctly in the
same capture, which is the tell.

## Rules

- **Seed through the client with the charset set** — `mysql --default-character-set=utf8mb4`, or
  `SET NAMES utf8mb4` as the first statement of the script — every time a seed carries non-ASCII text.
- **Verify a seed on the wire, never through the session that wrote it.** The capture *is* the
  verification; if there is no wire surface, verify with `HEX(LEFT(col, 20))` and compare to the
  expected UTF-8 bytes (`C5B3` for `ų`), which no session transcoding can disguise.
- **Repair in place** with the charset set on the session (`UPDATE … SET col = '<text>'`), or with
  `CONVERT(BINARY CONVERT(col USING latin1) USING utf8mb4)` when the original text is not at hand;
  then re-capture.
- **A doc that quotes seeded text must be copied from the capture, not transcribed from the CLI.** The
  captures README is the source; the guide cites it.

Pairs with the step-0 charset read in
[`../../plan/references/ADDITIVE_COLUMN_THROUGH_ALLOW_LISTED_WRITERS.md`](../../plan/references/ADDITIVE_COLUMN_THROUGH_ALLOW_LISTED_WRITERS.md)
(the *column's* charset, read from `information_schema`) — this note is about the *session's* charset,
which decides what bytes reach that column.
