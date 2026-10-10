#!/usr/bin/env bash
set -euo pipefail

# prose-lint.sh — scan text files for AI writing patterns
# Usage: prose-lint.sh <file ...>
# Requires: rg (ripgrep)

RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Word lists (kept in sync with SKILL.md) ---

BANNED_VOCAB=(
  delve tapestry woven intricate interplay
  underscore highlight showcase
  meticulous adept swift
  robust leverage nuanced
  additionally crucial pivotal vital
  enduring lasting foster cultivate
  enhance garner vibrant nestled
  breathtaking stunning testament profound
  spine
)

BANNED_ATMOSPHERIC=(
  liminal
)

# The article is part of each pattern: the tic is "stands as a testament", while
# "the review stands as posted" and "sub-features are" are plain English.
COPULA_AVOIDANCE=(
  "serves as" "stands as (a|an|the)" "marks (a|an)" "represents (a|an)"
  "boasts (a|an)" "features (a|an)" "offers (a|an)"
)

FILLER_PHRASES=(
  "in order to" "due to the fact" "it is important to note"
  "at this point in time" "has the ability to"
  "in the event that" "for the purpose of"
)

SYCOPHANTIC=(
  "great question" "you're absolutely right"
  "i hope this helps" "let me know if"
  "here is a" "of course!" "certainly!"
)

SIGNIFICANCE_PUFFERY=(
  "pivotal moment" "vital role" "key role"
  "broader trends" "evolving landscape"
  "enduring testament" "lasting legacy"
  "marking a" "shaping the" "setting the stage"
  "indelible mark" "deeply rooted"
  "the future looks bright" "exciting times"
)

NEGATIVE_PARALLELISMS=(
  "not only.*but also"
  "it's not just.*it's"
  "it's not merely.*it's"
  "doesn't just"
)

UNNECESSARY_WORDS=(
  genuinely currently literally precisely arguably
)

UNNECESSARY_PHRASES=(
  "in many ways" "to some extent" "it could be said"
  "it's worth noting"
)

# "Note that X" is filler only as the imperative that opens a sentence or a list
# item; "I sent the lane a note that the fix landed" uses the noun.
IMPERATIVE_NOTE="(^|[.!?:;(][[:space:]]+)[[:space:]]*([-*+]|[0-9]+[.)])?[[:space:]]*"
IMPERATIVE_NOTE+="(\\*\\*|__?)?(please )?(note|observe) that\\b"

BANNED_PHRASES=(
  "dive into" "align with" "in conclusion" "that said"
)

TAKEAWAY_ANNOUNCEMENTS=(
  "\\b(the (number worth carrying|thing to remember|interesting part|real story|key insight|key takeaway|important part)|what matters here) (is|was)\\b"
  "\\bthis is the (number|part|bit|thing) that\\b"
)

# Scoped to the summarising-predicate use only. The literal sense stays legal,
# so "identify the gap in prior work" must not match.
PUNCHLINE_ABSTRACTIONS=(
  "\\b(is|was|remains|becomes) the (gap|disconnect|tension|delta)\\b"
)

# --- Helpers ---

total_hits=0

# Prints the hit as `[category] "matched text"  whole line  file:line`. The
# matched text comes first so a reader of a long line can find the culprit.
warn() {
  local category="$1" span="$2" match="$3" file="$4" line="$5"
  ((total_hits++)) || true
  printf "${YELLOW}%-24s${RESET} ${RED}\"%s\"${RESET}  %s  ${CYAN}%s:%s${RESET}\n" \
    "[$category]" "$span" "$match" "$file" "$line"
}

# A phrase as a whole-word pattern: "here is a" must not match "there is a",
# nor "marks a" the start of "marks an".
phrase_re() {
  local re="\\b$1" word_end='[[:alnum:])]$'
  [[ "$1" =~ $word_end ]] && re+="\\b"
  printf '%s' "$re"
}

scan_pattern() {
  local category="$1" pattern="$2" span
  shift 2
  while IFS=: read -r file line match; do
    # Skip non-prose lines: markdown tables, imports, YAML frontmatter keys
    [[ "$match" =~ ^[[:space:]]*\| ]] && continue
    [[ "$match" =~ ^import[[:space:]] ]] && continue
    [[ "$match" =~ ^[a-z][a-zA-Z_-]*:([[:space:]]|$) ]] && continue
    # One hit per distinct match, so a second banned word on the line is not
    # hidden behind the first.
    while IFS= read -r span; do
      # Patterns that anchor on a neighbouring character carry it into the span.
      span=${span#"${span%%[[:alnum:]]*}"}
      warn "$category" "$span" "$match" "$file" "$line"
    done < <(rg -io -- "$pattern" <<<"$match" | awk '!seen[tolower($0)]++')
  done < <(rg -inH --no-heading -- "$pattern" "$@" 2>/dev/null || true)
}

# --- Determine input files ---

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  echo "Usage: prose-lint.sh [file ...]" >&2
  exit 1
fi

printf "${BOLD}Scanning %d file(s) for AI writing patterns...${RESET}\n\n" "${#files[@]}"

# --- 1. Banned vocabulary ---

# A banned word that ends a hyphenated compound is a term, not vocabulary:
# "obfuscation-robust features" names a property.
vocab_pattern=$(IFS='|'; echo "${BANNED_VOCAB[*]}")
scan_pattern "banned-vocab" "(^|[^-_[:alnum:]])($vocab_pattern)\\b" "${files[@]}"

# --- 2. Banned atmospheric words ---

atmo_pattern=$(IFS='|'; echo "${BANNED_ATMOSPHERIC[*]}")
scan_pattern "banned-atmospheric" "\\b($atmo_pattern)\\b" "${files[@]}"

# --- 3. Copula avoidance ---

for phrase in "${COPULA_AVOIDANCE[@]}"; do
  scan_pattern "copula-avoidance" "$(phrase_re "$phrase")" "${files[@]}"
done

# --- 4. Filler phrases ---

for phrase in "${FILLER_PHRASES[@]}"; do
  scan_pattern "filler-phrase" "$(phrase_re "$phrase")" "${files[@]}"
done

# --- 5. Sycophantic tone ---

for phrase in "${SYCOPHANTIC[@]}"; do
  scan_pattern "sycophantic" "$(phrase_re "$phrase")" "${files[@]}"
done

# --- 6. Significance puffery ---

for phrase in "${SIGNIFICANCE_PUFFERY[@]}"; do
  scan_pattern "significance-puffery" "$(phrase_re "$phrase")" "${files[@]}"
done

# --- 7. Negative parallelisms ---

for pattern in "${NEGATIVE_PARALLELISMS[@]}"; do
  scan_pattern "negative-parallelism" "$(phrase_re "$pattern")" "${files[@]}"
done

# --- 7b. Unnecessary words and hedge phrases ---

unnecessary_pattern=$(IFS='|'; echo "${UNNECESSARY_WORDS[*]}")
scan_pattern "unnecessary-word" "\\b($unnecessary_pattern)\\b" "${files[@]}"

for phrase in "${UNNECESSARY_PHRASES[@]}"; do
  scan_pattern "unnecessary-word" "\\b$phrase\\b" "${files[@]}"
done
scan_pattern "unnecessary-word" "$IMPERATIVE_NOTE" "${files[@]}"

# --- 7c. Banned multi-word phrases ---

for phrase in "${BANNED_PHRASES[@]}"; do
  scan_pattern "banned-vocab" "\\b$phrase\\b" "${files[@]}"
done

# --- 7d. Takeaway announcements ---

for pattern in "${TAKEAWAY_ANNOUNCEMENTS[@]}"; do
  scan_pattern "takeaway-announcement" "$pattern" "${files[@]}"
done

# --- 7e. Punchline abstractions ---

for pattern in "${PUNCHLINE_ABSTRACTIONS[@]}"; do
  scan_pattern "punchline-abstraction" "$pattern" "${files[@]}"
done

# --- 8. Excessive em dashes (3+ in one file) ---

for f in "${files[@]}"; do
  em_count=$(rg -c '—' "$f" 2>/dev/null || echo 0)
  if [[ "$em_count" -gt 3 ]]; then
    ((total_hits++)) || true
    printf "${YELLOW}%-24s${RESET} ${RED}%s em dashes${RESET}  ${CYAN}%s${RESET}\n" \
      "[excessive-em-dash]" "$em_count" "$f"
  fi
done

# --- 9. Superficial -ing phrases ---

ing_pattern="\\b(highlighting|underscoring|emphasizing|ensuring|"
ing_pattern+="reflecting|symbolizing|contributing to|cultivating|"
ing_pattern+="fostering|encompassing|showcasing)\\b"
scan_pattern "superficial-ing" "$ing_pattern" "${files[@]}"

# --- 10. Vague attribution ---

vague_pattern="(experts believe|industry observers|some critics argue|"
vague_pattern+="several sources|observers have cited)"
scan_pattern "vague-attribution" "$vague_pattern" "${files[@]}"

# --- 11. Rule of three (balanced "X, Y, and Z" tricolons) ---
# Heuristic: three short items (one to three words each) joined by two commas
# and "and"/"or", the last ending the clause. Short items are what make a
# tricolon rhetorical ("fast, reliable, and secure"); a list of clause-length
# steps ("loaded the image, appended the vars, and recreated the gateway") is a
# plain account and does not match. The first item must not follow a comma, so
# four-item lists (the recommended fix) do not match on their last three.

triad_item="[[:alnum:]'’-]+( [[:alnum:]'’-]+){0,2}"
triad_pattern="(^|[^,] )${triad_item}, ${triad_item},? (and|or) ${triad_item}([.;:!?)]|$)"
scan_pattern "rule-of-three" "$triad_pattern" "${files[@]}"

# --- Summary ---

echo ""
if [[ "$total_hits" -eq 0 ]]; then
  printf '%b' "${BOLD}No AI writing patterns detected.${RESET}\n"
else
  printf "${BOLD}Found %d potential AI writing pattern(s).${RESET}\n" "$total_hits"
fi

exit "$( [[ "$total_hits" -eq 0 ]] && echo 0 || echo 1 )"
