#!/usr/bin/env bash
set -euo pipefail

# prose-lint.sh — scan text files for AI writing patterns
# Usage: prose-lint.sh [file ...] or pipe via stdin
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
)

BANNED_ATMOSPHERIC=(
  liminal
)

COPULA_AVOIDANCE=(
  "serves as" "stands as" "marks a" "represents a"
  "boasts a" "features a" "offers a"
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

# --- Helpers ---

total_hits=0

warn() {
  local category="$1" match="$2" file="$3" line="$4"
  ((total_hits++)) || true
  printf "${YELLOW}%-24s${RESET} ${RED}%s${RESET}  ${CYAN}%s:%s${RESET}\n" \
    "[$category]" "$match" "$file" "$line"
}

scan_pattern() {
  local category="$1" pattern="$2"
  shift 2
  while IFS=: read -r file line match; do
    warn "$category" "$match" "$file" "$line"
  done < <(rg -inH --no-heading "$pattern" "$@" 2>/dev/null || true)
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

vocab_pattern=$(IFS='|'; echo "${BANNED_VOCAB[*]}")
scan_pattern "banned-vocab" "\\b($vocab_pattern)\\b" "${files[@]}"

# --- 2. Banned atmospheric words ---

atmo_pattern=$(IFS='|'; echo "${BANNED_ATMOSPHERIC[*]}")
scan_pattern "banned-atmospheric" "\\b($atmo_pattern)\\b" "${files[@]}"

# --- 3. Copula avoidance ---

for phrase in "${COPULA_AVOIDANCE[@]}"; do
  scan_pattern "copula-avoidance" "$phrase" "${files[@]}"
done

# --- 4. Filler phrases ---

for phrase in "${FILLER_PHRASES[@]}"; do
  scan_pattern "filler-phrase" "$phrase" "${files[@]}"
done

# --- 5. Sycophantic tone ---

for phrase in "${SYCOPHANTIC[@]}"; do
  scan_pattern "sycophantic" "$phrase" "${files[@]}"
done

# --- 6. Significance puffery ---

for phrase in "${SIGNIFICANCE_PUFFERY[@]}"; do
  scan_pattern "significance-puffery" "$phrase" "${files[@]}"
done

# --- 7. Negative parallelisms ---

for pattern in "${NEGATIVE_PARALLELISMS[@]}"; do
  scan_pattern "negative-parallelism" "$pattern" "${files[@]}"
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

# --- 11. Rule of three (X, Y, and Z repeated patterns) ---
# Heuristic: lines with 2+ commas followed by ", and"

scan_pattern "rule-of-three" ",.*,.*,\\s+and\\s+" "${files[@]}"

# --- Summary ---

echo ""
if [[ "$total_hits" -eq 0 ]]; then
  printf '%b' "${BOLD}No AI writing patterns detected.${RESET}\n"
else
  printf "${BOLD}Found %d potential AI writing pattern(s).${RESET}\n" "$total_hits"
fi

exit "$( [[ "$total_hits" -eq 0 ]] && echo 0 || echo 1 )"
