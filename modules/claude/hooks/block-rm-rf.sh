#!/bin/bash
set -euo pipefail
# Hook: Block rm -rf, suggest trash instead

CMD=$(jq -r '.tool_input.command // empty')
[[ -z "$CMD" ]] && exit 0

if echo "$CMD" | grep -qE 'rm[[:space:]]+-[^[:space:]]*r[^[:space:]]*f'; then
  jq -n '{
    decision: "block",
    reason: "Use trash instead of rm -rf. The trash command moves files to the system Trash (recoverable)."
  }'
  exit 0
fi

exit 0
