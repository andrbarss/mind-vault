#!/usr/bin/env bash
# Unit tests for the claude summary clean-vs-findings classification in
# tools/find_claude_comments.sh. The calibrated part is the pattern set the tool
# exports (CLAUDE_CLEAN_PATTERNS / CLAUDE_FINDING_MARKERS / CLAUDE_FINDING_NEGATIONS);
# this harness loads those exports from the tool itself, applies the tool's
# three-line decision to fixture bodies, and pins that the tool's classify pass
# still applies the negation strip before the marker search.
#
# Regression it exists for: a genuinely clean summary that enumerates passed checks
# ("- No map schemas missing captured examples") matched the marker \bmissing\b and
# was surfaced as FINDINGS=true.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$REPO_ROOT/tools/find_claude_comments.sh"
PASS=0
FAIL=0

# Load the exported patterns without running the tool (it calls gh).
eval "$(grep -E '^export CLAUDE_(CLEAN_PATTERNS|FINDING_MARKERS|FINDING_NEGATIONS|NOOP_PATTERNS|PARTIAL_REVIEW_PATTERNS)=' "$TOOL")"

classify() {
    python3 -c '
import os, re, sys
body = sys.stdin.read()
clean_re = re.compile(os.environ.get("CLAUDE_CLEAN_PATTERNS", "a^"), re.IGNORECASE)
finding_re = re.compile(os.environ.get("CLAUDE_FINDING_MARKERS", "a^"), re.IGNORECASE)
neg_re = re.compile(os.environ.get("CLAUDE_FINDING_NEGATIONS", "a^"), re.IGNORECASE)
marker_body = neg_re.sub(" ", body)
is_clean = bool(clean_re.search(body)) and not finding_re.search(marker_body)
print("clean" if is_clean else "findings")
'
}

assert_class() {
    local name="$1" expected="$2" body="$3" actual
    actual=$(printf '%s' "$body" | classify)
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1)); echo "  ✓ $name → $actual"
    else
        FAIL=$((FAIL + 1)); echo "  ✗ $name → expected $expected, got $actual"
    fi
}

echo "claude summary classification"

assert_class "clean summary enumerating passed checks with a negated 'missing'" clean \
'## Code review

No issues found. Checked for bugs and CLAUDE.md compliance.

### Review findings

**OpenAPI annotations** — All rules satisfied:
- No `additionalProperties=true`
- No map schemas missing captured examples
- One HTTP verb per path'

assert_class "plain clean summary" clean \
'## Code review

No issues found. Checked for bugs and CLAUDE.md compliance.'

assert_class "clean list item with a negated 'violations'" clean \
'## Code review

No bugs found.

- No violations of the status-code rule'

assert_class "mixed review: a clean section and a missing item on its own line" findings \
'## Code review

### Bugs
No issues found.

### Docs
- Docstrings missing on `load_rows()`'

assert_class "a 'No …' line that also says found / except is not a passed check" findings \
'## Code review

No issues found except that the migration is missing its down file.'

assert_class "negated clause followed by a real finding in the same line" findings \
'## Code review

No issues found.
- Zero handlers missing auth; 2 routes missing tests'

assert_class "clean summary whose checklist says '(no violation)' mid-line" clean \
'## Code review

No issues found. Checked for bugs and CLAUDE.md compliance.

### What was checked

- **CLAUDE.md compliance**: `additionalProperties` prohibition (no violation), map-schema example requirement (no violation), one verb per path.
- **Bugs**: the integer-key guard, the empty-array path (none missing). All correct.'

assert_class "a negated parenthetical does not hide a real finding later in the line" findings \
'## Code review

No issues found.
- `additionalProperties` prohibition (no violation), but `PriceMap` is missing its captured example'

assert_class "a parenthetical with an exception is not a passed check" findings \
'## Code review

No issues found.
- status-code rule (no violation except in `fooAction`)'

assert_class "count line" findings \
'## Code review

One issue found.

### `app/service.py`'

# The tool itself must apply the strip before the marker search — otherwise the
# patterns above pass while the shipped classifier still false-positives.
if grep -q "marker_body = neg_re.sub(' ', body)" "$TOOL" && grep -q "finding_re.search(marker_body)" "$TOOL"; then
    PASS=$((PASS + 1)); echo "  ✓ tool classify pass strips negations before the marker search"
else
    FAIL=$((FAIL + 1)); echo "  ✗ tool classify pass does not strip negations before the marker search"
fi

# --- Summary selection: which bodies are verdicts at all (before clean-vs-findings).
# A no-op (draft / already-reviewed skip) and a summary that says it did not re-review
# the head are not verdicts; a findings body is always a verdict.
select_body() {
    python3 -c '
import os, re, sys
body = sys.stdin.read()
noop_re = re.compile(os.environ.get("CLAUDE_NOOP_PATTERNS", "a^"), re.IGNORECASE | re.MULTILINE)
partial_re = re.compile(os.environ.get("CLAUDE_PARTIAL_REVIEW_PATTERNS", "a^"), re.IGNORECASE)
finding_re = re.compile(os.environ.get("CLAUDE_FINDING_MARKERS", "a^"), re.IGNORECASE)
neg_re = re.compile(os.environ.get("CLAUDE_FINDING_NEGATIONS", "a^"), re.IGNORECASE)
partial = bool(partial_re.search(body)) and not finding_re.search(neg_re.sub(" ", body))
print("no-verdict" if (noop_re.search(body) or partial) else "verdict")
'
}

assert_select() {
    local name="$1" expected="$2" body="$3" actual
    actual=$(printf '%s' "$body" | select_body)
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1)); echo "  ✓ $name → $actual"
    else
        FAIL=$((FAIL + 1)); echo "  ✗ $name → expected $expected, got $actual"
    fi
}

echo ""
echo "claude summary selection (verdict vs no-verdict)"

assert_select "docs-only push: clean phrase but did not re-run the agent review (field case)" no-verdict \
'## Code review

No issues found. Checked for bugs and CLAUDE.md compliance.

Verification run on head `1cc5fe9` (PR merge ref). The code was already reviewed clean at `1b303b1`. I did not re-run the agent review for this head, because the commits since then (the `/wrap`) only touch docs.
- `composer test`: `OK (2678 tests, 23532 assertions)`'

assert_select "the did-not-re-review spelling" no-verdict \
'## Code review

No issues found. I didn'"'"'t re-review the documentation commits.'

assert_select "a findings body that also says it did not re-run something stays a verdict" verdict \
'## Code review

One issue found. I did not re-run the agent review for the unchanged files.

### `docs/README.md`'

assert_select "a full clean review is a verdict" verdict \
'## Code review

No issues found. Checked for bugs and CLAUDE.md compliance.'

assert_select "draft skip is not a verdict" no-verdict \
'## Code review

Skipped — this pull request is still in **draft** status.'

# The tool itself must apply the partial-review exclusion in its summary selection.
if grep -q "def is_partial_noop(body):" "$TOOL" && grep -q "and not is_partial_noop(body))" "$TOOL"; then
    PASS=$((PASS + 1)); echo "  ✓ tool summary selection excludes did-not-re-review summaries"
else
    FAIL=$((FAIL + 1)); echo "  ✗ tool summary selection does not exclude did-not-re-review summaries"
fi

echo ""
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
