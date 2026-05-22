#!/bin/bash

alias claude::yolo="claude --dangerously-skip-permissions"

_claude_aliases_dir="${${(%):-%x}:A:h}"

claude::jnj() {
  set -a
  source "${_claude_aliases_dir}/.env.jnj"
  set +a
  claude "$@"
}

_claude_ant_link() {
  # ln -sfn replaces an existing symlink atomically; no-op when target matches.
  local target=$1 link=$2
  [[ -e $target ]] || return 0
  [[ -L $link && $(readlink "$link") == "$target" ]] && return 0
  ln -sfn "$target" "$link"
}

_claude_ant_ensure() {
  local ant=$HOME/.claude-ant
  local dotfiles=$HOME/.files/modules
  mkdir -p "$ant"
  _claude_ant_link "$dotfiles/agents/AGENTS.md"     "$ant/CLAUDE.md"
  _claude_ant_link "$dotfiles/agents/skills"        "$ant/skills"
  _claude_ant_link "$dotfiles/claude/mcp.json"      "$ant/mcp.json"
  _claude_ant_link "$dotfiles/claude/settings.ant.json" "$ant/settings.json"
  _claude_ant_link "$HOME/.claude/commands"         "$ant/commands"
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
  set -a
  source "${_claude_aliases_dir}/.env.ant"
  set +a
  CLAUDE_CONFIG_DIR="$HOME/.claude-ant" \
    CMUX_PRESERVE_CLAUDE_AUTH_SELECTION_ENV=1 \
    claude "$@"
}

claude::local() {
  ANTHROPIC_BASE_URL=http://localhost:1234 \
  ANTHROPIC_AUTH_TOKEN=lmstudio \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  claude "$@"
}
