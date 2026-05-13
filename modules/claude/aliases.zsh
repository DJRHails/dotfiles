#!/bin/bash

alias claude::yolo="claude --dangerously-skip-permissions"

_claude_aliases_dir="${${(%):-%x}:A:h}"

claude::jnj() {
  set -a
  source "${_claude_aliases_dir}/.env.jnj"
  set +a
  claude "$@"
}

claude::local() {
  ANTHROPIC_BASE_URL=http://localhost:1234 \
  ANTHROPIC_AUTH_TOKEN=lmstudio \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  claude "$@"
}
