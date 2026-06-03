#!/usr/bin/env bash
set -euo pipefail
# Fork the current Claude Code session into a new cmux split pane (or tab).
#
# Opens a split (or sibling tab) in the caller's cmux workspace, launches a forked copy of
# the current session in it (claude --resume <id> --fork-session, with the right
# CLAUDE_CONFIG_DIR), titles it "<prefix><session-name>", and pre-seeds the
# fork's tab-sync hook state so the title is not overwritten on the fork's first
# turn (see sync-cmux-tab.sh).
#
# Context is read entirely from the environment that Claude Code + cmux inject
# (no process-tree walking): CLAUDE_CODE_SESSION_ID, CLAUDE_CONFIG_DIR,
# CMUX_SURFACE_ID, CMUX_WORKSPACE_ID.
#
# Local vs remote: every cmux mutation goes through `cmux rpc <method>` (surface.split
# / surface.create / surface.send_text / tab.action). rpc is forwarded identically by
# the local app and the remote relay, so the same code path works whether the session
# runs on the cmux UI host or on a remote host (e.g. bonbon) — unlike the high-level
# verbs (rename-tab, identify, …) which the remote relay CLI does not expose.
#
# Usage: fork-session.sh [title-prefix] [where]
#   title-prefix  default "fork: "
#   where         right|left|up|down  -> split in that direction (default: right)
#                 tab                 -> new sibling tab instead of a split

PREFIX="${1:-fork: }"
WHERE="${2:-right}"

die() {
  echo "fork-session: $*" >&2
  exit 1
}

# --- context (all from env) --------------------------------------------------
[[ -n "${CMUX_SURFACE_ID:-}" ]] || die "not inside a cmux surface (CMUX_SURFACE_ID unset)"
[[ -n "${CMUX_WORKSPACE_ID:-}" ]] || die "CMUX_WORKSPACE_ID unset"
command -v cmux >/dev/null 2>&1 || die "cmux CLI not found on PATH"
command -v jq >/dev/null 2>&1 || die "jq not found on PATH"

SID="${CLAUDE_CODE_SESSION_ID:-}"
[[ -n "$SID" ]] || die "CLAUDE_CODE_SESSION_ID unset (run inside a Claude Code session)"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SESSIONS_DIR="$CFG/sessions"

# session name + project cwd from the sessions file whose .sessionId matches.
INFO=$(jq -r --arg s "$SID" \
  'select(.sessionId==$s) | "\(.name // "")\t\(.cwd // "")"' \
  "$SESSIONS_DIR"/*.json 2>/dev/null | head -1)
NAME="${INFO%%$'\t'*}"
PROJ="${INFO#*$'\t'}"
[[ -n "$PROJ" ]] || PROJ="$PWD"
TITLE="${PREFIX}${NAME:-$SID}"

# Pick the launcher that matches the session's config dir. The new tab is an
# interactive shell, so the user's claude::* wrapper functions are available.
# Matching the wrapper matters: claude::ant sources auth (.env.ant) and runs its
# ensure step, which a bare `CLAUDE_CONFIG_DIR=... claude` skips (→ "Not logged
# in"). Fall back to an explicit env prefix for unknown config dirs.
case "$CFG" in
*/.claude-ant) LAUNCH="claude::ant" ;;
*/.claude) LAUNCH="claude" ;;
*) LAUNCH="CLAUDE_CONFIG_DIR=$(printf '%q' "$CFG") claude" ;;
esac
FORK_CMD="cd $(printf '%q' "$PROJ") && $LAUNCH --resume $(printf '%q' "$SID") --fork-session"

# --- create the surface, launch the fork, title it — all via rpc --------------
# snapshot existing session ids so we can find the fork's new id afterwards.
before=$(jq -r '.sessionId' "$SESSIONS_DIR"/*.json 2>/dev/null | sort -u)

case "$WHERE" in
left | right | up | down)
  res=$(cmux rpc surface.split \
    "$(jq -nc --arg s "$CMUX_SURFACE_ID" --arg d "$WHERE" '{surface_id:$s,direction:$d}')") ||
    die "rpc surface.split failed"
  ;;
tab)
  res=$(cmux rpc surface.create '{}') || die "rpc surface.create failed"
  ;;
*)
  die "unknown 'where': $WHERE (use right|left|up|down|tab)"
  ;;
esac
NEW=$(jq -r '.surface_id // empty' <<<"$res")
[[ -n "$NEW" ]] || die "no surface_id in rpc response: $res"

sleep 2 # let the new shell initialise before sending input
cmux rpc surface.send_text \
  "$(jq -nc --arg s "$NEW" --arg t "$FORK_CMD"$'\n' '{surface_id:$s,text:$t}')" >/dev/null ||
  die "rpc surface.send_text failed"

cmux rpc tab.action \
  "$(jq -nc --arg s "$NEW" --arg n "$TITLE" '{action:"rename",tab_id:$s,title:$n}')" >/dev/null 2>&1 || true

# Keep the title: the fork inherits NAME, so its own tab-sync hook would reset
# the tab to NAME on its first turn. Pre-seeding state=NAME makes that hook a
# no-op. Poll briefly for the fork's freshly-written sessions file.
if [[ -n "$NAME" ]]; then
  state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-cmux-tab"
  mkdir -p "$state_dir"
  for _ in $(seq 1 20); do
    fork_id=$(jq -r --arg s "$SID" --arg p "$PROJ" --arg n "$NAME" \
      'select(.sessionId!=$s and .cwd==$p and .name==$n) | .sessionId' \
      "$SESSIONS_DIR"/*.json 2>/dev/null | grep -vxF "$before" | head -1) || true
    if [[ -n "$fork_id" ]]; then
      printf '%s' "$NAME" >"$state_dir/$fork_id"
      break
    fi
    sleep 1
  done
fi

echo "forked $SID -> $WHERE ($NEW) titled '$TITLE'"
