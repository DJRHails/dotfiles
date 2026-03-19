#!/bin/bash
set -euo pipefail
# Hook: Block direct push to main/master

CMD=$(jq -r '.tool_input.command // empty')
[[ -z "$CMD" ]] && exit 0

if echo "$CMD" | grep -qE 'git[[:space:]]+push.*(main|master)'; then
  jq -n '{
    decision: "block",
    reason: "Direct push to main/master blocked. Use feature branches and PRs instead."
  }'
  exit 0
fi

exit 0
