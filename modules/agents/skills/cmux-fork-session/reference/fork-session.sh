#!/usr/bin/env bash
set -euo pipefail
# Fork the current Claude Code session into a new cmux split pane (or tab).
#
# Opens a split (or sibling tab) in the caller's cmux workspace, launches a forked copy of
# the current session in it (claude --resume <id> --fork-session, with the right
# CLAUDE_CONFIG_DIR), titles it "<prefix><session-name>", and pre-seeds the fork's
# tab-sync hook state so the title is not overwritten on the fork's first turn
# (see sync-cmux-tab.sh).
#
# Context is read from the env cmux + Claude Code inject: CLAUDE_CODE_SESSION_ID,
# CLAUDE_CONFIG_DIR, CMUX_SURFACE_ID, CMUX_WORKSPACE_ID — except the surface id, which we
# prefer to read live from the sidecar (see "stale surface id" below).
#
# Local vs remote — the three problems this script solves:
#
#   1. Reaching the cmux app. Every mutation goes through `cmux rpc <method>` against the
#      app socket. On the cmux UI host (the mac) we call the app binary directly; on a
#      durable/mosh remote (e.g. bonbon) that socket isn't reachable, so we ssh to the app
#      host and run *its* cmux against *its* socket (args base64-encoded per-arg so the JSON
#      survives ssh re-quoting). Same shim as cmux-session-tab.
#
#   2. Stale surface id. cmux re-mints workspace/surface UUIDs per app-restart, so the
#      forwarded $CMUX_SURFACE_ID goes stale and splitting against it fails ("Workspace not
#      found"). The zellij attach scripts write the *live* ids to a sidecar on every
#      (re)connect; we read the surface id from there, keyed by $ZELLIJ_SESSION_NAME.
#
#   3. The fork must land back on the remote. A split makes a fresh shell *on the mac*; on a
#      durable remote the session's cwd and `claude` live on the remote, so a bare cd would
#      fail. In remote mode we write a one-pane zellij layout *here* (we run on the remote)
#      that launches the fork, then drive the new mac surface to `mosh <remote> -- zellij
#      attach` it — so the fork ends up in its own durable zellij session on the remote.
#
# Usage: fork-session.sh [title-prefix] [where]
#   title-prefix  default "fork: "
#   where         right|left|up|down  -> split in that direction (default: right)
#                 tab                 -> new sibling tab instead of a split

PREFIX="${1:-fork: }"
WHERE="${2:-right}"
DURABLE_HOST="${CMUX_DURABLE_HOST:-$(hostname -s)}" # mosh target the fork hops back to

die() {
  echo "fork-session: $*" >&2
  exit 1
}

# Shared cmux transport (run_cmux / cmux_is_local / CMUX_APP_HOST / CMUX_APP_BIN),
# kept in one place so this script and the rename hook can't drift — e.g. the socket
# path move ("~/Library/Application Support/cmux" -> "~/.local/state/cmux") that
# broke the old hardcode. APP_HOST/APP_CMUX stay as aliases for the refs below.
# shellcheck source=/dev/null
source "${CMUX_REMOTE_LIB:-$HOME/.files/modules/claude/hooks/lib/cmux-remote.sh}"
APP_HOST="$CMUX_APP_HOST"
APP_CMUX="$CMUX_APP_BIN"

if [ -x "$APP_CMUX" ]; then MODE=local; else MODE=remote; fi

command -v jq >/dev/null 2>&1 || die "jq not found on PATH"

# --- context: claude session name + project cwd + launcher --------------------
SID="${CLAUDE_CODE_SESSION_ID:-}"
[[ -n "$SID" ]] || die "CLAUDE_CODE_SESSION_ID unset (run inside a Claude Code session)"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SESSIONS_DIR="$CFG/sessions"

INFO=$(jq -r --arg s "$SID" \
  'select(.sessionId==$s) | "\(.name // "")\t\(.cwd // "")"' \
  "$SESSIONS_DIR"/*.json 2>/dev/null | head -1)
NAME="${INFO%%$'\t'*}"
PROJ="${INFO#*$'\t'}"
[[ -n "$PROJ" ]] || PROJ="$PWD"
TITLE="${PREFIX}${NAME:-$SID}"

# --- targeting: resolve THIS session's live cmux surface ------------------------------
# Map the session to its surface by the one key that is focus-independent and survives cmux
# re-minting UUIDs across app restarts: the surface *title*. The tab-sync hook propagates
# the Claude session name out as the terminal title (Claude session → zellij/mosh → cmux
# surface title), so the surface whose title contains NAME is ours. Locally we trust the
# fresh $CMUX_SURFACE_ID instead (cmux injects it per surface; no app round-trip needed).
# NOT the forwarded env or the live-ids sidecar (both go stale), and NOT "focused" (drifts).
SURFACE="${CMUX_SURFACE_ID:-}"
LIVE_WS="${CMUX_WORKSPACE_ID:-}"
sidecar="${XDG_CACHE_HOME:-$HOME/.cache}/cmux-zellij/live-${ZELLIJ_SESSION_NAME:-}"
if [ "$MODE" = remote ]; then
  [ -n "$NAME" ] || die "session has no name yet — /rename it so its tab title can be matched"
  tree=$(run_cmux --id-format both tree --all 2>/dev/null) || die "cmux tree failed (app host unreachable?)"
  match=$(printf '%s\n' "$tree" | awk -v name="$NAME" '
    /workspace workspace:/ {
      if (match($0, /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/)) ws = substr($0, RSTART, RLENGTH)
    }
    /surface surface:/ && index($0, name) {
      if (match($0, /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/)) {
        print substr($0, RSTART, RLENGTH), ws
        exit
      }
    }')
  SURFACE="${match%% *}"
  LIVE_WS="${match#* }"
  [ -n "$SURFACE" ] || die "no cmux surface titled with session name \"$NAME\" (is the tab-sync hook running?)"
  # Heal the sidecar so cmux-session-tab / the tab-sync hook pick up the live id too.
  if [ -n "${ZELLIJ_SESSION_NAME:-}" ]; then
    mkdir -p "$(dirname "$sidecar")"
    printf '%s %s\n' "${LIVE_WS:-unknown}" "$SURFACE" >"$sidecar"
  fi
fi
[ -n "$SURFACE" ] || die "no surface id (CMUX_SURFACE_ID unset and not resolvable)"

# Pick the launcher that matches the session's config dir. claude::ant sources auth
# (.env.ant) + runs its ensure step; a bare `CLAUDE_CONFIG_DIR=… claude` skips that
# (→ "Not logged in"). The fork runs in an interactive shell, so the wrapper is available.
case "$CFG" in
*/.claude-ant) LAUNCH="claude::ant" ;;
*/.claude) LAUNCH="claude" ;;
*) LAUNCH="CLAUDE_CONFIG_DIR=$(printf '%q' "$CFG") claude" ;;
esac
FORK_CMD="cd $(printf '%q' "$PROJ") && $LAUNCH --resume $(printf '%q' "$SID") --fork-session"

# --- create the new surface ---------------------------------------------------
before=$(jq -r '.sessionId' "$SESSIONS_DIR"/*.json 2>/dev/null | sort -u)

case "$WHERE" in
left | right | up | down)
  res=$(run_cmux rpc surface.split \
    "$(jq -nc --arg s "$SURFACE" --arg d "$WHERE" '{surface_id:$s,direction:$d}')") ||
    die "rpc surface.split failed"
  ;;
tab)
  res=$(run_cmux rpc surface.create '{}') || die "rpc surface.create failed"
  ;;
*)
  die "unknown 'where': $WHERE (use right|left|up|down|tab)"
  ;;
esac
NEW=$(jq -r '.surface_id // empty' <<<"$res")
[[ -n "$NEW" ]] || die "no surface_id in rpc response: $res"

# --- launch the fork in the new surface ---------------------------------------
if [ "$MODE" = local ]; then
  # The new surface is a shell on this (the cmux UI) host — same machine as the session.
  sleep 2 # let the new shell initialise before sending input
  run_cmux rpc surface.send_text \
    "$(jq -nc --arg s "$NEW" --arg t "$FORK_CMD"$'\n' '{surface_id:$s,text:$t}')" >/dev/null ||
    die "rpc surface.send_text failed"
else
  # The new surface is a fresh login shell on the mac, but the session + cwd + claude live on
  # this remote. Write a one-pane layout here that launches the fork in a NEW durable zellij
  # session, then drive the mac surface to mosh back here and start it. `zsh -lc` (login,
  # non-interactive) gets PATH but does NOT source .zshrc, so auto-attach.zsh does not fire and
  # fight us; the layout pane's `zsh -ic` is interactive so claude::ant resolves, and
  # auto-attach there no-ops because $ZELLIJ is already set.
  if command -v humane >/dev/null 2>&1; then
    fork_tag="$(humane id --short "$NEW-$SID" 2>/dev/null)"
  fi
  [ -n "${fork_tag:-}" ] || fork_tag="${NEW:0:8}"
  forksess="cmux-${DURABLE_HOST}-fork-${fork_tag}"
  forksess="${forksess//[^a-zA-Z0-9-]/-}"
  layout="/tmp/cmux-fork-${forksess}.kdl"
  printf 'layout {\n    pane command="zsh" {\n        args "-ic" "%s"\n    }\n}\n' "$FORK_CMD" >"$layout"

  # Sidecar so the fork is itself controllable via cmux-session-tab (rename/focus) later:
  # keyed by its zellij session name, col 2 = the fork's live surface id.
  scdir="${XDG_CACHE_HOME:-$HOME/.cache}/cmux-zellij"
  mkdir -p "$scdir"
  printf '%s %s\n' "${LIVE_WS:-unknown}" "$NEW" >"$scdir/live-$forksess"

  # --new-session-with-layout *creates* a named session (plain --session attaches and errors if
  # it doesn't exist). Three robustness rules, learned the hard way under load:
  #   (1) The new split's login shell takes a beat to reach a prompt, and input typed too early is
  #       silently dropped. So FIRST confirm the shell is live with an idempotent marker echo
  #       (safe to resend) — the split runs on the app host, so the marker file appearing there is
  #       proof input is being consumed. Only then send the hop.
  #   (2) The hop is `exec mosh …`, which REPLACES the split shell with mosh on the first send — a
  #       resend would then be typed as keystrokes into the live mosh/zellij pane, not a shell. So
  #       send the hop exactly ONCE; never resend after the exec.
  #   (3) mosh bootstrap + zellij create can take a while under load, so poll generously (~36s)
  #       for the session to come up (we run on the fork's own host → local list-sessions is
  #       authoritative). The old "resend every 3s for 18s" both under-waited and corrupted the
  #       pane with stray keystrokes.
  hop="exec mosh ${DURABLE_HOST} -- env TMPDIR=/tmp zsh -lc 'TMPDIR=/tmp zellij --new-session-with-layout ${layout} --session ${forksess}'"

  # (1) shell-ready handshake
  marker="/tmp/cmux-fork-ready-${forksess}"
  ready=""
  for _ in $(seq 1 12); do
    run_cmux rpc surface.send_text \
      "$(jq -nc --arg s "$NEW" --arg t "echo ready > $marker"$'\n' '{surface_id:$s,text:$t}')" \
      >/dev/null 2>&1 || true
    sleep 2
    if [ "$MODE" = remote ]; then
      ssh "$APP_HOST" "[ -f '$marker' ]" 2>/dev/null && ready=ok && break
    else
      [ -f "$marker" ] && ready=ok && break
    fi
  done
  [ "$MODE" = remote ] && ssh "$APP_HOST" "rm -f '$marker'" 2>/dev/null || rm -f "$marker" 2>/dev/null
  [ -n "$ready" ] || die "new split's shell never reached a prompt on ${APP_HOST}"

  # (2) launch the fork — send the exec hop exactly once
  run_cmux rpc surface.send_text \
    "$(jq -nc --arg s "$NEW" --arg t "$hop"$'\n' '{surface_id:$s,text:$t}')" >/dev/null 2>&1 || true

  # (3) poll-only for the durable session (no resend)
  launched=""
  for _ in $(seq 1 18); do
    if zellij list-sessions 2>/dev/null | sed -E 's/\x1b\[[0-9;]*m//g' |
      awk -v s="$forksess" '$1==s{f=1} END{exit f?0:1}'; then
      launched=ok
      break
    fi
    sleep 2
  done
  [ -n "$launched" ] || die "fork hop sent but session '$forksess' never came up on ${DURABLE_HOST}"
fi

run_cmux rpc tab.action \
  "$(jq -nc --arg s "$NEW" --arg n "$TITLE" '{action:"rename",tab_id:$s,title:$n}')" >/dev/null 2>&1 || true

# Keep the title: the fork inherits NAME, so its own tab-sync hook would reset the tab to
# NAME on its first turn. Pre-seeding state=NAME makes that hook a no-op. Poll briefly for
# the fork's freshly-written sessions file (on this host — that's where the fork runs).
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

echo "forked $SID -> $WHERE ($NEW) [$MODE] titled '$TITLE'"
