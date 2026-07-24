#!/usr/bin/env bash
# Fail if any glassine rule in .gitattributes matches zero tracked files.
#
# Failure mode this catches: a folder that was encrypted gets renamed/moved,
# the .gitattributes rule is forgotten, and files at the new path commit as
# plaintext while the old rule lingers pointing at nothing.
#
# Override (after you've confirmed the rule is intentionally retired):
#   ALLOW_DEAD_CRYPT_RULES=1 git commit ...
#
# Exit codes:
#   0  all crypt patterns match >=1 tracked file
#   1  at least one pattern matches nothing and override is not set

set -euo pipefail

if [ "${ALLOW_DEAD_CRYPT_RULES:-0}" = "1" ]; then
  echo "check-crypt-patterns: skipped (ALLOW_DEAD_CRYPT_RULES=1)" >&2
  exit 0
fi

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

# Collect all .gitattributes files (excluding nested repos and .git internals)
mapfile -t attr_files < <(
  find . -name .gitattributes -type f \
    -not -path "./.git/*" \
    -not -path "./.data/repo/*" \
    2>/dev/null
)

dead_count=0
dead_report=""

for attr in "${attr_files[@]}"; do
  # Patterns are relative to the directory containing .gitattributes
  attr_dir=$(dirname "$attr")

  while IFS= read -r line; do
    # Strip comments / blanks
    line="${line%%#*}"
    [ -z "${line// /}" ] && continue
    # Only glassine-filtered rules
    case "$line" in
      *filter=glassine*) ;;
      *) continue ;;
    esac

    # First whitespace-delimited token is the pattern
    pattern=$(echo "$line" | awk '{print $1}')
    # Resolve relative-to-attr-dir if necessary
    if [ "$attr_dir" != "." ]; then
      full_pattern="${attr_dir#./}/$pattern"
    else
      full_pattern="$pattern"
    fi

    # git ls-files returns matched tracked files; pattern matching is glob-style
    count=$(git ls-files -- "$full_pattern" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -eq 0 ]; then
      dead_count=$((dead_count + 1))
      dead_report="${dead_report}  - ${full_pattern}  (declared in ${attr#./})"$'\n'
    fi
  done < "$attr"
done

if [ "$dead_count" -gt 0 ]; then
  cat >&2 <<EOF
check-crypt-patterns: $dead_count dead glassine pattern(s) — these match no tracked files:

${dead_report}
Likely cause: a folder that used to live at this path was moved or renamed,
but .gitattributes wasn't updated. Files at the new path are now committing
as PLAINTEXT.

Fix options:
  (a) Update the pattern to the new path, then re-stage:
        git rm --cached <files>
        git add <files>           # glassine filter re-runs, files encrypt
  (b) Delete the rule if encryption is genuinely no longer wanted.
  (c) Override (only if you accept files committing in plaintext for now):
        ALLOW_DEAD_CRYPT_RULES=1 git commit ...

EOF
  exit 1
fi

exit 0
