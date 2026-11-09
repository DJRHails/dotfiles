#!/usr/bin/env bash
# Behaviour suite for bin/mdunwrap. Self-contained: `bash tests/mdunwrap.test.sh`.
# Exits non-zero on failure.
#
# mdunwrap rewrites files in place, so a reflow bug does not fail loudly: it merges two
# bullets into one, swallows a table row into a paragraph, or joins the lines of a code
# block, and the file still looks like markdown. Each case below pins one structure that
# must survive, plus the two invariants that catch anything unforeseen: the word stream
# is unchanged, and a second pass changes nothing.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
tool="$repo_root/bin/mdunwrap"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

fails=0

ok() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  fails=$((fails + 1))
}

# expect_line <label> <fixture-file> <exact line that must appear in the output>
expect_line() {
  local label="$1" fixture="$2" line="$3"
  if python3 "$tool" "$fixture" | grep -qxF -- "$line"; then ok "$label"; else
    fail "$label: expected line not found: $line"
    python3 "$tool" "$fixture" | sed 's/^/     | /'
  fi
}

# expect_count <label> <fixture-file> <grep -E pattern> <expected count>
expect_count() {
  local label="$1" fixture="$2" pattern="$3" want="$4" got
  got="$(python3 "$tool" "$fixture" | grep -cE -- "$pattern")"
  if [[ "$got" == "$want" ]]; then ok "$label"; else fail "$label: wanted $want lines matching $pattern, got $got"; fi
}

cat >"$work/paragraphs.md" <<'EOF'
# Title

A paragraph that was
hard-wrapped over three
lines by an editor.

Second paragraph, one
line break.
EOF
expect_line "paragraph joins onto one line" "$work/paragraphs.md" "A paragraph that was hard-wrapped over three lines by an editor."
expect_line "heading untouched" "$work/paragraphs.md" "# Title"
expect_count "paragraphs stay separate" "$work/paragraphs.md" '^(A paragraph|Second paragraph)' 2

cat >"$work/lists.md" <<'EOF'
- First bullet whose text
  wraps onto a second line.
- Second bullet.
  - Nested bullet that also
    wraps.
- Third bullet with a lazy
continuation line.

1. **Delta sentence.** What is new
   against the previous experiment.
2. **Protocol.** The swapped slots
   only.
EOF
expect_line "bullet continuation joins" "$work/lists.md" "- First bullet whose text wraps onto a second line."
expect_line "nested bullet keeps its indent and joins" "$work/lists.md" "  - Nested bullet that also wraps."
expect_line "lazy continuation joins" "$work/lists.md" "- Third bullet with a lazy continuation line."
expect_count "sibling bullets never merge" "$work/lists.md" '^- ' 3
expect_line "numbered item joins" "$work/lists.md" "1. **Delta sentence.** What is new against the previous experiment."
expect_count "numbered items stay separate" "$work/lists.md" '^[0-9]+\. ' 2

cat >"$work/verbatim.md" <<'EOF'
Intro line.

```markdown
## <Claim> {#sec:slug}
<Delta from the previous
experiment.>
```

| move | what it does |
| --- | --- |
| verdict | restates the heading |

<!-- outline: a comment that
     spans two lines -->

$$
a = b
+ c
$$

Closing
line.
EOF
expect_count "fenced code lines untouched" "$work/verbatim.md" '^(<Delta from the previous|experiment\.>)$' 2
expect_count "table rows untouched" "$work/verbatim.md" '^\|' 3
expect_count "multi-line comment untouched" "$work/verbatim.md" '^(<!-- outline: a comment that|     spans two lines -->)$' 2
expect_count "maths block untouched" "$work/verbatim.md" '^(a = b|\+ c)$' 2
expect_line "paragraph after verbatim blocks still joins" "$work/verbatim.md" "Closing line."

cat >"$work/quote.md" <<'EOF'
> **A claim.** Each x-axis label
> corresponds to a pair, with
> whiskers for the mean.
>
> - a bullet in the quote
>   that wraps
EOF
expect_line "blockquote paragraph joins under one prefix" "$work/quote.md" "> **A claim.** Each x-axis label corresponds to a pair, with whiskers for the mean."
expect_line "quote paragraph separator survives" "$work/quote.md" ">"
expect_line "list inside a quote joins" "$work/quote.md" "> - a bullet in the quote that wraps"

cat >"$work/front.md" <<'EOF'
---
name: some-skill
description: >-
  How a results section is built,
  folded over two lines.
tags:
  - one
  - two
---

Body text that
wraps.
EOF
expect_line "front-matter folded scalar joins" "$work/front.md" "  How a results section is built, folded over two lines."
expect_line "front-matter list untouched" "$work/front.md" "  - one"
expect_line "front-matter name untouched" "$work/front.md" "name: some-skill"
expect_line "body after front matter joins" "$work/front.md" "Body text that wraps."

printf 'Line with a hard break  \nnext line kept separate\nbut this one joins  \nafter a second break.\n' >"$work/breaks.md"
expect_line "hard break keeps the following line separate" "$work/breaks.md" "Line with a hard break  "
expect_line "lines after a hard break join, and a mid-paragraph break survives" "$work/breaks.md" "next line kept separate but this one joins  "
expect_line "the line after a mid-paragraph break stays separate" "$work/breaks.md" "after a second break."

# Invariants over every fixture: word stream unchanged, second pass is a no-op.
for fixture in "$work"/*.md; do
  name="$(basename "$fixture")"
  before="$(tr -s '[:space:]' ' ' <"$fixture" | sed 's/> //g')"
  after="$(python3 "$tool" "$fixture" | tr -s '[:space:]' ' ' | sed 's/> //g')"
  if [[ "$before" == "$after" ]]; then ok "word stream unchanged: $name"; else fail "word stream changed: $name"; fi
  once="$(python3 "$tool" "$fixture")"
  twice="$(printf '%s\n' "$once" | python3 "$tool")"
  if [[ "$once" == "$twice" ]]; then ok "idempotent: $name"; else fail "second pass changed: $name"; fi
done

# Modes: stdin filter, --check exit codes, -i rewrites only when needed.
if [[ "$(printf 'a\nb\n' | python3 "$tool")" == "a b" ]]; then ok "stdin filter"; else fail "stdin filter"; fi
if python3 "$tool" --check "$work/paragraphs.md" 2>/dev/null; then fail "--check exits 0 on a wrapped file"; else ok "--check exits 1 on a wrapped file"; fi
cp "$work/paragraphs.md" "$work/inplace.md"
python3 "$tool" -i "$work/inplace.md" 2>/dev/null
if python3 "$tool" --check "$work/inplace.md" 2>/dev/null; then ok "-i rewrites, then --check exits 0"; else fail "-i left the file wrapped"; fi
if [[ "$(python3 "$tool" -i "$work/inplace.md" 2>&1)" == "" ]]; then ok "-i is silent when nothing changes"; else fail "-i rewrote an already-flat file"; fi

if [[ "$fails" -gt 0 ]]; then
  echo "mdunwrap: $fails failure(s)" >&2
  exit 1
fi
echo "mdunwrap: all checks passed"
