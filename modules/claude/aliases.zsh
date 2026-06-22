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
  # Subshell: keep .env.ant's ANTHROPIC_API_KEY scoped to this launch — leaked
  # into the shell it outranks profiles on every later ant/claude call.
  # Auth comes from the API key alone: ANTHROPIC_CONFIG_DIR points the
  # ant-profile lookup at an empty dir so claude doesn't also see
  # ~/.config/anthropic's profiles and warn about ambiguous auth.
  (
    set -a
    source "${_claude_aliases_dir}/.env.ant"
    set +a
    CLAUDE_CONFIG_DIR="$HOME/.claude-ant" \
      ANTHROPIC_CONFIG_DIR="$HOME/.claude-ant/anthropic" \
      CMUX_PRESERVE_CLAUDE_AUTH_SELECTION_ENV=1 \
      claude "$@"
  )
}

# claude::ant::safe lives in modules/claude/safe.zsh (transcrypt-encrypted).

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

# Resume a session by id, cd-ing into its original directory first. Claude can
# only --resume a session from the cwd it was started in, and session-search
# only prints the bare `claude --resume <id>`. This resolves both the directory
# and the owning config profile so a copy-pasted id Just Works.
claude::resume() {
  emulate -L zsh
  local id=$1
  [[ -n $id ]] || { echo "claude::resume: usage: claude::resume <session-id>" >&2; return 1; }

  # Search every config-dir variant (default + ant) and the legacy agents dir.
  local file
  file=$(command find "$HOME/.claude" "$HOME/.claude-ant" "$HOME/.agents" \
           -type f -name "${id}.jsonl" -print 2>/dev/null | head -1)
  [[ -n $file ]] || { echo "claude::resume: no session '$id' under ~/.claude*, ~/.agents" >&2; return 1; }

  # The encoded project dir is lossy ('/' and '.' both collapse to '-'), so read
  # the real working directory from the transcript's cwd field instead. Use jq,
  # not a regex: transcripts may be written compact ("cwd":"...") or spaced
  # ("cwd": "..."), and only a JSON parser handles both plus any path escaping.
  local dir
  dir=$(command jq -r '.cwd? // empty' "$file" 2>/dev/null | head -1)
  [[ -n $dir && -d $dir ]] || { echo "claude::resume: cannot resolve cwd for '$id' ($file)" >&2; return 1; }

  cd "$dir" || return 1

  # Route through the profile whose config dir owns the session so --resume finds
  # it (and the ant profile gets its env + self-healing links).
  case ${file%%/projects/*} in
    "$HOME/.claude-ant") claude::ant --resume "$id" ;;
    "$HOME/.claude")     claude --resume "$id" ;;
    *)                   CLAUDE_CONFIG_DIR=${file%%/projects/*} claude --resume "$id" ;;
  esac
}

claude::local() {
  ANTHROPIC_BASE_URL=http://localhost:1234 \
  ANTHROPIC_AUTH_TOKEN=lmstudio \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  claude "$@"
}
