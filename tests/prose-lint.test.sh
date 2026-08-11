#!/usr/bin/env bash
# Behavior suite for modules/agents/skills/prose-conventions/prose-lint.sh.
# Self-contained: `bash tests/prose-lint.test.sh`. Exits non-zero on failure.
#
# The takeaway-announcement and punchline-abstraction rules are scoped in a way
# a word list cannot express: `the gap` is banned only as the predicate of a
# summarising sentence, and stays legal in its literal sense — which the guide
# itself relies on ("Identify the gap in existing approaches"). Folding those
# nouns into BANNED_VOCAB is the obvious "simplification" and it silently
# breaks the carve-out, so both directions are pinned here.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
lint="$repo_root/modules/agents/skills/prose-conventions/prose-lint.sh"

if ! command -v rg > /dev/null 2>&1; then
  echo "SKIP prose-lint: needs ripgrep" >&2
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

fails=0

# Reports the categories prose-lint.sh raises for a single line of prose.
categories_for() {
  printf '%s\n' "$1" > "$work/sample.md"
  bash "$lint" "$work/sample.md" 2>/dev/null \
    | sed -e 's/\x1b\[[0-9;]*m//g' \
    | grep -o '\[[a-z-]*\]' || true
}

flags() {
  local label="$1" category="$2" line="$3"
  if categories_for "$line" | grep -qx "\[$category\]"; then
    printf 'ok   %s\n' "$label"
  else
    printf 'FAIL %s: expected [%s] for: %s\n' "$label" "$category" "$line"
    ((fails++))
  fi
}

ignores() {
  local label="$1" category="$2" line="$3"
  if categories_for "$line" | grep -qx "\[$category\]"; then
    printf 'FAIL %s: unexpected [%s] for: %s\n' "$label" "$category" "$line"
    ((fails++))
  else
    printf 'ok   %s\n' "$label"
  fi
}

# --- takeaway announcements are caught --------------------------------------

flags "number worth carrying" takeaway-announcement \
  "The number worth carrying is 4.2 percent."
flags "what matters here" takeaway-announcement \
  "What matters here is that latency halved."
flags "key insight" takeaway-announcement \
  "The key insight is that caching wins."
flags "real story" takeaway-announcement \
  "The real story is in the tail."
flags "this is the number that" takeaway-announcement \
  "This is the number that matters."

# --- abstract nouns as a punchline are caught -------------------------------

flags "is the gap" punchline-abstraction \
  "The number worth carrying is the gap between the two runs."
flags "remains the tension" punchline-abstraction \
  "What is left over remains the tension in the design."

# --- the literal sense stays legal ------------------------------------------
# Each of these appears in the repo's own prose; a false positive here trains
# the reader to ignore the category.

ignores "identify the gap" punchline-abstraction \
  "Identify the gap in existing approaches."
ignores "closed the gap" punchline-abstraction \
  "We closed the gap by rewriting the parser."
ignores "physical tension" punchline-abstraction \
  "The tension in the rope measured 40 newtons."
ignores "delta as a diff" punchline-abstraction \
  "Review only the new delta against the previously-reviewed head."
ignores "plain statement of a number" takeaway-announcement \
  "Throughput rose from 900 to 1,340 requests per second."

if ((fails)); then
  printf '\n%d check(s) failed\n' "$fails"
  exit 1
fi
printf '\nall checks passed\n'
