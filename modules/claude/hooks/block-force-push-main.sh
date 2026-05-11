#!/bin/bash
set -euo pipefail
# Hook: Block force pushes to main/master branches
#
# Decision logic:
#   1. If the command explicitly pushes to `main` or `master`, block.
#   2. Otherwise resolve the branch from (in order): any `cd <path>` prefix in
#      the command, the tool's `cwd` field, and finally the process cwd.
#      Block only if that branch is main/master.
#
# Why the fallback chain: the hook runs from the parent Claude session's cwd,
# which may differ from the worktree the force-push actually targets (e.g.
# subagents running in `.data/worktrees/...`). Using the command's `cd` prefix
# or the tool-reported cwd avoids false positives on feature branches.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$CMD" ]] && exit 0

# Only care about git push with force variants: --force, --force-with-lease, -f
if ! echo "$CMD" | grep -qE 'git[[:space:]]+push[[:space:]]'; then
  exit 0
fi
if ! echo "$CMD" | grep -qE '(^|[[:space:]])(-f|--force([-[:alpha:]]*)?)([[:space:]=]|$)'; then
  exit 0
fi

block() {
  jq -n '{
    decision: "block",
    reason: "Force push to main/master is not allowed. Use a feature branch."
  }'
  exit 0
}

# 1. Explicit `git push ... main|master` — any arg after `git push` that is
# exactly `main` or `master` counts as an explicit target.
PUSH_ARGS=$(echo "$CMD" | sed -nE 's/.*git[[:space:]]+push[[:space:]]+(.*)/\1/p')
if [[ -n "$PUSH_ARGS" ]]; then
  for tok in $PUSH_ARGS; do
    if [[ "$tok" == "main" || "$tok" == "master" ]]; then
      block
    fi
  done
fi

# 2. Resolve branch from the actual target directory.
CD_PATH=$(echo "$CMD" | sed -nE 's/^[[:space:]]*cd[[:space:]]+("[^"]+"|[^[:space:]&|;]+).*/\1/p' | tr -d '"' | head -1)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

BRANCH=""
for dir in "$CD_PATH" "$CWD" "."; do
  [[ -z "$dir" ]] && continue
  [[ ! -d "$dir" ]] && continue
  BRANCH=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  [[ -n "$BRANCH" && "$BRANCH" != "HEAD" ]] && break
done

if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  block
fi

exit 0
