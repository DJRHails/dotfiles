#!/bin/bash

alias claude::yolo="claude --dangerously-skip-permissions"

# Make bypass-permissions reachable in the shift+tab cycle on every launch,
# without activating it (sessions still start in their configured default mode).
# Uses `command` to call the binary directly, so this never recurses and the
# claude::* helpers below inherit the flag through their `claude "$@"` calls.
claude() { command claude --allow-dangerously-skip-permissions "$@"; }

_claude_aliases_dir="${${(%):-%x}:A:h}"

claude::jnj() {
  local env_file="${_claude_aliases_dir}/.env.jnj"
  [[ -f $env_file ]] || { echo "claude::jnj: missing $env_file — refusing to launch on the default account" >&2; return 1; }
  # Subshell: keep the sourced credentials scoped to this launch instead of
  # leaking them into the interactive shell.
  (
    set -a
    source "$env_file"
    set +a
    claude "$@"
  )
}

_claude_ant_link() {
  # ln -sfn replaces an existing symlink atomically; no-op when target matches.
  local target=$1 link=$2
  [[ -e $target ]] || return 0
  [[ -L $link && $(readlink "$link") == "$target" ]] && return 0
  ln -sfn "$target" "$link"
}

_claude_ant_ensure() {
  # Repo links mirror modules/{agents,claude}/symlinks.conf — the source of
  # truth applied by bootstrap.sh; this only self-heals them at launch.
  # Optional arg: config dir to populate (default ~/.claude-ant).
  local ant=${1:-$HOME/.claude-ant}
  local dotfiles=$HOME/.files/modules
  mkdir -p "$ant"
  _claude_ant_link "$dotfiles/agents/AGENTS.md"     "$ant/CLAUDE.md"
  _claude_ant_link "$dotfiles/agents/skills"        "$ant/skills"
  _claude_ant_link "$dotfiles/agents/commands"      "$ant/commands"
  _claude_ant_link "$dotfiles/agents/subagents"     "$ant/agents"
  _claude_ant_link "$dotfiles/claude/mcp.json"      "$ant/mcp.json"
  _claude_ant_link "$dotfiles/claude/settings.ant.json" "$ant/settings.json"
  # Runtime state shared with the default profile (not in symlinks.conf).
  _claude_ant_link "$HOME/.claude/plugins"          "$ant/plugins"
  # Mirror the current cwd's memory dir so KB-style auto-memory survives the
  # profile split. Slug is the absolute cwd with '/' → '-' (Claude Code convention).
  local slug="${PWD//\//-}"
  local src="$HOME/.claude/projects/$slug/memory"
  if [[ -d $src ]]; then
    mkdir -p "$ant/projects/$slug"
    _claude_ant_link "$src" "$ant/projects/$slug/memory"
  fi
}

claude::ant() {
  _claude_ant_ensure
  mkdir -p "$HOME/.claude-ant/anthropic"
  # Auth is the personal claude.ai login stored for this config dir
  # (first launch: /login). An ambient API key or token would outrank it, so
  # unset them in a subshell; ANTHROPIC_CONFIG_DIR points the ant-profile
  # lookup at an empty dir so ~/.config/anthropic's profiles can't compete.
  (
    unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
    CLAUDE_CONFIG_DIR="$HOME/.claude-ant" \
      ANTHROPIC_CONFIG_DIR="$HOME/.claude-ant/anthropic" \
      CMUX_PRESERVE_CLAUDE_AUTH_SELECTION_ENV=1 \
      claude "$@"
  )
}

# claude::ant::safe lives in modules/claude/safe.zsh (glassine-encrypted).

# One-shot prompt via `ant messages create`, parameterized by env so a session
# can set the target once: ANT_MODEL (required), ANT_PROFILE (default safe),
# ANT_MAX_TOKENS (default 1024). Prompt is the joined arguments (or stdin when
# piped). Prints the text reply; pass extra flags via ANT_FLAGS if needed.
#   ANT_MODEL=claude-boiler-v3 ant::msg "Reply with exactly: ok"
ant::msg() {
  local prompt="$*"
  [[ -z $prompt && ! -t 0 ]] && prompt="$(cat)"
  [[ -n $prompt ]] || { echo "ant::msg: no prompt given (args or stdin)" >&2; return 1; }
  [[ -n $ANT_MODEL ]] || { echo "ant::msg: set ANT_MODEL (try: ant models list)" >&2; return 1; }
  # </dev/null: ant treats piped stdin as a JSON request body, which would
  # fight the --message flag when the prompt arrives via pipe.
  ANTHROPIC_PROFILE="${ANT_PROFILE:-safe}" ant messages create \
    --model "$ANT_MODEL" \
    --max-tokens "${ANT_MAX_TOKENS:-1024}" \
    --message "$(jq -cn --arg c "$prompt" '{role: "user", content: $c}')" \
    --format json < /dev/null | jq -r '.content[0].text'
}

# Accept either a Claude or Codex session UUID (or a unique prefix).
source "${${(%):-%x}:A:h}/../session-resume/resume.zsh"
claude::resume() { _agent_session_resume claude "$@"; }
