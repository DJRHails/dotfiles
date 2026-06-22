#!/bin/bash
#
# Subscription switchers for pi (@earendil-works/pi-coding-agent).
#
# Unlike Claude Code (one account per CLAUDE_CONFIG_DIR), pi keeps every
# subscription in a single ~/.pi/agent and selects one per invocation via
# --provider/--model. The OAuth Codex providers are named by pi itself
# (openai-codex, openai-codex-2) and cannot be renamed — pi resolves them by
# those built-in names — so the switchers below put a readable name on top.
#
# Accounts (see ~/.pi/agent/auth.json):
#   ant-fellow-high-prio  Anthropic Fellows gateway, default interactive (opus 4.8)
#   ant-fellow-batch      same gateway, batch tier (cheap async)
#   openai-codex          ChatGPT Team Codex seat — email/password sign-in
#   openai-codex-2        same Team workspace — Google sign-in

pi::ant()        { pi --provider ant-fellow-high-prio --model 'claude-opus-4-8[fast]' "$@"; }
pi::ant-batch()  { pi --provider ant-fellow-batch     --model 'claude-opus-4-8'       "$@"; }
pi::codex()      { pi --provider openai-codex          --model gpt-5.5                 "$@"; }
pi::codex-google() { pi --provider openai-codex-2      --model gpt-5.5                 "$@"; }

# Resume a session by id, cd-ing into its original directory first — the pi
# analogue of claude::resume. pi resumes by partial UUID (`--session <id>`) but
# only finds the session from its original cwd, which session-search prints as
# `pi::resume <id>`.
pi::resume() {
  emulate -L zsh
  local id=$1
  [[ -n $id ]] || { echo "pi::resume: usage: pi::resume <session-id>" >&2; return 1; }

  # Sessions live at <config>/agent/sessions/<encoded-cwd>/<timestamp>_<uuid>.jsonl.
  # Search every config-dir variant in case isolated PI_CODING_AGENT_DIR profiles
  # are added later.
  local file
  file=$(command find "$HOME"/.pi*/agent/sessions -type f -name "*${id}*.jsonl" \
           -print 2>/dev/null | head -1)
  [[ -n $file ]] || { echo "pi::resume: no session '$id' under ~/.pi*/agent/sessions" >&2; return 1; }

  # The session header line (type=session) records the real cwd.
  local dir
  dir=$(command grep -m1 -o '"cwd":"[^"]*"' "$file" | cut -d'"' -f4)
  [[ -n $dir && -d $dir ]] || { echo "pi::resume: cannot resolve cwd for '$id' ($file)" >&2; return 1; }

  cd "$dir" || return 1

  # Route through the config dir that owns the session.
  local cfg=${file%%/agent/sessions/*}
  if [[ $cfg == "$HOME/.pi" ]]; then
    pi --session "$id"
  else
    PI_CODING_AGENT_DIR=$cfg pi --session "$id"
  fi
}
