#!/bin/bash
#
# Subagent pane startup: this interactive zsh takes ~1.1-1.4s to boot, well over the
# subagents extension's 500ms default wait before it writes the launch command into a
# fresh pane. That race dropped the command -> blank pane -> "stalled" subagent. Give
# it comfortable headroom so the launch always lands.
export PI_SUBAGENT_SHELL_READY_DELAY_MS=3000
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
#   glm                   self-hosted GLM 5.2 (llama.cpp) — registered by the
#                         glm-provider.ts extension; endpoint/key in
#                         ~/.files/modules/pi/.env.glm

pi::ant()        { pi --provider ant-fellow-high-prio --model 'claude-opus-4-8[fast]' "$@"; }
pi::ant-batch()  { pi --provider ant-fellow-batch     --model 'claude-opus-4-8'       "$@"; }
pi::codex()      { pi --provider openai-codex          --model gpt-5.5                 "$@"; }
pi::codex-google() { pi --provider openai-codex-2      --model gpt-5.5                 "$@"; }
pi::glm() {
  emulate -L zsh
  local env_file="$HOME/.files/modules/pi/.env.glm"

  # Resolve endpoint/key the way glm-provider.ts does: process env wins, else
  # the .env.glm file (KEY=VALUE, optional `export ` prefix / surrounding quotes).
  local base_url=${GLM_BASE_URL:-} api_key=${GLM_API_KEY:-}
  if [[ -f $env_file ]]; then
    [[ -n $base_url ]] || base_url=$(sed -n -E 's/^[[:space:]]*(export[[:space:]]+)?GLM_BASE_URL=//p' "$env_file" | head -1)
    [[ -n $api_key ]] || api_key=$(sed -n -E 's/^[[:space:]]*(export[[:space:]]+)?GLM_API_KEY=//p' "$env_file" | head -1)
  fi
  base_url=${${base_url#[\"\']}%[\"\']}
  api_key=${${api_key#[\"\']}%[\"\']}

  if [[ -z $base_url ]]; then
    echo "pi::glm: GLM_BASE_URL is unset (checked env and $env_file)" >&2
    echo "pi::glm: set the GLM tunnel URL in: $env_file" >&2
    return 1
  fi

  # Probe /models before launching. A rotated trycloudflare tunnel (its DNS no
  # longer resolves) is the usual failure; on any error point at the file to fix.
  if ! curl -fsS --connect-timeout 3 --max-time 6 -o /dev/null \
    -H "Authorization: Bearer $api_key" "${base_url%/}/models" 2>/dev/null; then
    echo "pi::glm: GLM endpoint not responding at ${base_url%/}/models" >&2
    echo "pi::glm: the trycloudflare tunnel likely rotated — update GLM_BASE_URL (and key) in: $env_file" >&2
    return 1
  fi

  pi --provider glm --model glm-5-2 "$@"
}

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

  # The session header line (type=session) records the real cwd. Use jq, not a
  # regex, so both compact ("cwd":"...") and spaced ("cwd": "...") JSON parse.
  local dir
  dir=$(command jq -r '.cwd? // empty' "$file" 2>/dev/null | head -1)
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
