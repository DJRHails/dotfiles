#!/bin/bash
set -euo pipefail
# Hook: Block rm -rf, suggest trash instead

CMD=$(jq -r '.tool_input.command // empty')
[[ -z "$CMD" ]] && exit 0

# Match recursive+force in any order/format: -rf, -fr, -Rf, -r -f,
# --recursive --force, flags after operands. Split the command on
# separators (;, |, &, newline) so each rm is checked against only
# its own flags.
RECURSIVE_FLAG='(^|[[:space:]])(-[[:alnum:]]*[rR][[:alnum:]]*|--recursive)([[:space:]]|$)'
FORCE_FLAG='(^|[[:space:]])(-[[:alnum:]]*f[[:alnum:]]*|--force)([[:space:]]|$)'

while IFS= read -r segment; do
  echo "$segment" | grep -qE '(^|[[:space:]])rm([[:space:]]|$)' || continue
  if echo "$segment" | grep -qE "$RECURSIVE_FLAG" \
    && echo "$segment" | grep -qE "$FORCE_FLAG"; then
    jq -n '{
      decision: "block",
      reason: "Use trash instead of rm -rf. The trash command moves files to the system Trash (recoverable)."
    }'
    exit 0
  fi
done < <(echo "$CMD" | tr ';|&\n' '\n\n\n\n')

exit 0
