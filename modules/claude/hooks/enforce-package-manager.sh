#!/bin/bash
set -euo pipefail
# Hook: Enforce correct package manager per project
# Blocks npm in pnpm projects, pip in uv projects

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$CMD" ]] && exit 0

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[[ -z "$CWD" ]] && exit 0

# Block npm in pnpm projects
if [[ -f "${CWD}/pnpm-lock.yaml" ]] && echo "$CMD" | grep -qE '^npm\s'; then
  jq -n '{
    decision: "block",
    reason: "This project uses pnpm, not npm. Use pnpm instead."
  }'
  exit 0
fi

# Block pip install in uv projects
if [[ -f "${CWD}/uv.lock" ]] && echo "$CMD" | grep -qE '^pip[3]?\s+install'; then
  jq -n '{
    decision: "block",
    reason: "This project uses uv, not pip. Use uv pip install or uv add instead."
  }'
  exit 0
fi

exit 0
