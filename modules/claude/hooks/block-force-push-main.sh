#!/bin/bash
set -euo pipefail
# Hook: Block force pushes to main/master branches

CMD=$(jq -r '.tool_input.command // empty')
[[ -z "$CMD" ]] && exit 0

# Only care about git push with --force variants
if ! echo "$CMD" | grep -qE 'git\s+push\s.*--force'; then
  exit 0
fi

# Check current branch
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  jq -n '{
    decision: "block",
    reason: "Force push to main/master is not allowed. Use a feature branch."
  }'
  exit 0
fi

# Allow force push on feature branches
exit 0
