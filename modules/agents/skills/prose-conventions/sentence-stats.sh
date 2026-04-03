#!/usr/bin/env bash
set -euo pipefail

# sentence-stats.sh — sentence length and rhythm analysis
# Usage: sentence-stats.sh <file>
# Reports: word counts per sentence, flags >40 words, shows rhythm variety

if [[ $# -lt 1 ]]; then
  echo "Usage: sentence-stats.sh <file>" >&2
  exit 1
fi

file="$1"

if [[ ! -f "$file" ]]; then
  echo "File not found: $file" >&2
  exit 1
fi

# Strip markdown headers, links, code blocks, and blank lines
# Split on sentence-ending punctuation
# Count words per sentence

awk '
  /^```/ { in_code = !in_code; next }
  in_code { next }
  /^#/ { next }
  /^[-*] / { sub(/^[-*] /, "") }
  /^[0-9]+\. / { sub(/^[0-9]+\. /, "") }
  /^\s*$/ { next }
  {
    # Remove markdown formatting
    gsub(/\[([^\]]*)\]\([^\)]*\)/, "\\1")  # links
    gsub(/[*_`~]/, "")                       # bold/italic/code
    gsub(/!\[([^\]]*)\]/, "")                # images

    print
  }
' "$file" | \
# Split into sentences and count words
awk '
  BEGIN {
    total = 0; count = 0; over40 = 0; under10 = 0
    max = 0; min = 9999
  }
  {
    # Accumulate text
    buf = buf " " $0
  }
  END {
    # Split on sentence boundaries
    n = split(buf, sentences, /[.!?]+[ \t\n]+|[.!?]+$/)
    for (i = 1; i <= n; i++) {
      # Count words in sentence
      gsub(/^[ \t\n]+|[ \t\n]+$/, "", sentences[i])
      if (sentences[i] == "") continue

      wc = split(sentences[i], words, /[ \t]+/)
      if (wc < 3) continue  # skip fragments

      count++
      total += wc
      lengths[count] = wc

      if (wc > max) max = wc
      if (wc < min) min = wc
      if (wc > 40) over40++
      if (wc < 10) under10++

      # Print each sentence with word count
      if (wc > 40) {
        printf "\033[0;31m%3d words\033[0m  %s\n", wc, substr(sentences[i], 1, 80)
      } else if (wc > 30) {
        printf "\033[0;33m%3d words\033[0m  %s\n", wc, substr(sentences[i], 1, 80)
      } else {
        printf "\033[2m%3d words\033[0m  %s\n", wc, substr(sentences[i], 1, 80)
      }
    }

    if (count == 0) {
      print "No sentences found."
      exit
    }

    avg = total / count

    # Calculate standard deviation for rhythm variety
    sum_sq = 0
    for (i = 1; i <= count; i++) {
      diff = lengths[i] - avg
      sum_sq += diff * diff
    }
    stddev = sqrt(sum_sq / count)

    printf "\n\033[1m--- Summary ---\033[0m\n"
    printf "Sentences:    %d\n", count
    printf "Average:      %.1f words\n", avg
    printf "Range:        %d - %d words\n", min, max
    printf "Std dev:      %.1f (rhythm variety)\n", stddev

    if (over40 > 0)
      printf "\033[0;31mOver 40 words: %d sentence(s)\033[0m\n", over40

    if (stddev < 4)
      printf "\033[0;33mLow variety (stddev < 4) — sentences are too uniform in length\033[0m\n"
    else
      printf "\033[0;32mGood rhythm variety\033[0m\n"

    if (under10 == 0 && count > 5)
      printf "\033[0;33mNo short punchy sentences (<10 words) — consider adding some\033[0m\n"
  }
'
