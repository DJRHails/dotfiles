#!/bin/bash
set -euo pipefail
# Hook (Stop): keep the cmux surface/tab name in step with the Claude session
# name (the value set by /rename). cmux already syncs the *workspace* name; the
# tab/surface is not synced, so we do it here.
#
#   1. Read this session's name from <config>/sessions/<pid>.json — the file whose
#      .sessionId matches the hook's session_id (config dir derived from
#      transcript_path so we don't hardcode ~/.claude or ~/.claude-ant).
#   2. cmux rename-tab the caller surface ($CMUX_SURFACE_ID) to that name.
#
# Robust + safe: silent no-op outside cmux, before any /rename, or if cmux is
# missing; a per-session state file means we only call rename when the name
# actually changes (no per-turn churn); never blocks the Stop event.

INPUT=$(cat)

# Only meaningful inside a cmux-spawned surface.
SURFACE="${CMUX_SURFACE_ID:-}"
[[ -n "$SURFACE" ]] || exit 0
command -v cmux >/dev/null 2>&1 || exit 0

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-cmux-tab"
mkdir -p "$STATE_DIR"

# Rename method depends on the host's cmux CLI: the full macOS CLI has
# `rename-tab`; the remote relay CLI (cmuxd-remote) lacks it but forwards
# arbitrary JSON-RPC, so we fall back to `rpc tab.action` (tab_id is the
# surface-targeting param — `tab`/`surface` are ignored). Probe + cache per host.
CAP_FILE="$STATE_DIR/.rename-method.$(hostname 2>/dev/null || echo unknown)"
if [[ ! -f "$CAP_FILE" ]]; then
  help=$(cmux --help 2>&1)
  if grep -q 'rename-tab' <<<"$help"; then echo rename-tab >"$CAP_FILE"
  elif grep -qE '(^| )rpc ' <<<"$help"; then echo rpc >"$CAP_FILE"
  else echo none >"$CAP_FILE"; fi
fi
METHOD=$(cat "$CAP_FILE" 2>/dev/null || echo none)
[[ "$METHOD" == "none" ]] && exit 0

SESSION_ID=$(jq -r '.session_id // empty' <<<"$INPUT")
TRANSCRIPT=$(jq -r '.transcript_path // empty' <<<"$INPUT")
[[ -n "$SESSION_ID" && -n "$TRANSCRIPT" ]] || exit 0

# <config>/projects/<proj>/<id>.jsonl -> <config>
CONFIG_DIR=$(dirname "$(dirname "$(dirname "$TRANSCRIPT")")")
SESSIONS_DIR="$CONFIG_DIR/sessions"
[[ -d "$SESSIONS_DIR" ]] || exit 0

# The session name (.name) is absent until the first /rename — no clobber then.
NAME=$(jq -r --arg sid "$SESSION_ID" \
  'select(.sessionId==$sid) | .name // empty' "$SESSIONS_DIR"/*.json 2>/dev/null | head -1)
[[ -n "$NAME" ]] || exit 0

# Only call rename when the name actually changed since we last synced.
STATE_FILE="$STATE_DIR/$SESSION_ID"
[[ "$(cat "$STATE_FILE" 2>/dev/null || true)" == "$NAME" ]] && exit 0

ok=""
case "$METHOD" in
rename-tab)
  cmux rename-tab --surface "$SURFACE" "$NAME" >/dev/null 2>&1 && ok=1
  ;;
rpc)
  params=$(jq -nc --arg t "$SURFACE" --arg n "$NAME" '{action:"rename",tab_id:$t,title:$n}')
  cmux rpc tab.action "$params" >/dev/null 2>&1 && ok=1
  ;;
esac
[[ -n "$ok" ]] && printf '%s' "$NAME" >"$STATE_FILE"
exit 0
