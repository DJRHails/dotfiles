#!/bin/bash
set -euo pipefail
# Hook: Block long python -c commands (>10 lines). Write a script instead.

CMD=$(jq -r '.tool_input.command // empty')
[[ -z "$CMD" ]] && exit 0

# Check if it's a python -c command
if echo "$CMD" | grep -qE 'python[0-9.]* -c'; then
  # Count total lines of the command — multi-line python -c will have many
  LINE_COUNT=$(echo "$CMD" | wc -l | tr -d ' ')

  if [[ "$LINE_COUNT" -gt 10 ]]; then
    jq -n '{
      decision: "block",
      reason: "python -c commands over 10 lines should be written as scripts. Use scripts/ for permanent scripts or .data/ for truly temporary ones."
    }'
    exit 0
  fi
fi

exit 0
