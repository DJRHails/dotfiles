#!/usr/bin/env bash
# Fail if any glassine-encrypted tracked file is not excluded by .dockerignore.
#
# Failure mode this catches: a new path gets a glassine rule in .gitattributes but
# no .dockerignore entry. The working tree is DECRYPTED, so `docker build` copies
# that file into an image layer as plaintext.
#
# A file counts as excluded when the file itself or one of its parent directories
# is listed verbatim in .dockerignore. Globs are not evaluated, and any `!`
# re-include line fails the check outright, since it could undo an exclusion.
#
# Exit codes:
#   0  every glassine-encrypted file is excluded
#   1  at least one is not, or .dockerignore is missing or has a re-include line

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

if [ ! -f .dockerignore ]; then
  echo "check-dockerignore-crypt: .dockerignore not found at $repo_root" >&2
  exit 1
fi

if grep -nE '^[[:space:]]*!' .dockerignore >&2; then
  echo "check-dockerignore-crypt: .dockerignore has re-include (!) lines (above);" \
    "they could put encrypted paths back into the build context." >&2
  exit 1
fi

# Normalise entries: drop comments and blanks, leading "/" or "./", trailing "/".
excluded=$(sed -E -e 's/^[[:space:]]+|[[:space:]]+$//g' -e '/^(#|$)/d' \
  -e 's#^\.?/##' -e 's#/+$##' .dockerignore)

is_excluded() {
  local path=$1
  while [ -n "$path" ] && [ "$path" != "." ]; do
    grep -qxF -- "$path" <<<"$excluded" && return 0
    path=$(dirname "$path")
  done
  return 1
}

missing=""
while IFS= read -r file; do
  is_excluded "$file" || missing="${missing}  - ${file}"$'\n'
done < <(git ls-files -z | git check-attr -z --stdin filter |
  tr '\0' '\n' | paste - - - | awk -F'\t' '$3 == "glassine" { print $1 }')

if [ -n "$missing" ]; then
  cat >&2 <<EOF
check-dockerignore-crypt: glassine-encrypted files not excluded by .dockerignore:

${missing}
The working tree is decrypted, so docker build would copy these into the image
as plaintext. Add the glassine rule's path (as written in .gitattributes, minus
any trailing /**) to .dockerignore.
EOF
  exit 1
fi

exit 0
