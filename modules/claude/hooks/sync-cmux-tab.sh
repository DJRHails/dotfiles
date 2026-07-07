#!/bin/bash
set -Eeuo pipefail
# A non-zero UserPromptSubmit hook BLOCKS the prompt — including automated wakes
# (background-task notifications), which stranded headless gantry workers when
# this hook died under set -e. Fail open: any unexpected error is a silent no-op.
trap 'exit 0' ERR
# Hook (UserPromptSubmit + Stop): keep the cmux panel (the per-surface tab in a
# pane's tab bar) in step with the Claude session name (set by /rename). cmux
# already syncs the *workspace* name; the panel/surface tab is not, so we do it.
#
# Event choice: /rename is a client-side metadata command that fires NO hook of
# its own (verified on v2.1.196 — like /model), so we sync on the next event.
# UserPromptSubmit (the user's next message) is the earliest — it fires ~1 turn
# before Stop with the renamed .name already on disk, so the panel updates as
# soon as the user types again. Stop is kept as a backstop and is the event
# cmux-fork-session's pre-seed is tuned around (it writes our state file before a
# fork's first turn so the fork keeps its "fork:" title). NOT SessionStart — it
# fires at session boot and would race/lose that pre-seed, clobbering the fork
# title. This hook emits nothing on stdout (safe for UserPromptSubmit, whose
# stdout would otherwise be injected into the model's context).
#
# Local vs remote (this hook runs wherever `claude` runs):
#   - Local (the cmux UI host): cmux injects a fresh, reliable $CMUX_SURFACE_ID.
#   - Remote (durable/mosh box with no cmux, e.g. bonbon): $CMUX_SURFACE_ID is
#     stale, and `cmux` isn't installed — so we reach the mac's cmux over ssh via
#     run_cmux (shared with cmux-fork-session) and resolve our surface by *title*
#     (the focus-independent key fork-session uses): the title currently holds our
#     last-synced name, or the zellij session name before the first sync.
#
# Rename uses the `tab.action` JSON-RPC, not `cmux rename-tab`: the subcommand
# fails with "Tab not found" on current cmux builds and the remote relay lacks it;
# `tab.action` is the stable interface. It silently falls back to renaming the
# *focused* surface on an unresolvable tab_id, so we (a) confirm our surface id is
# a live surface before calling and (b) confirm cmux acted on *our* surface after,
# before recording the sync — together these stop us clobbering the active tab.
#
# Robust: silent no-op outside cmux, before any /rename, or if the transport is
# unreachable; a per-session state file means we only rename when the name
# actually changes (no per-turn churn — so the remote ssh round-trips happen only
# on a rename, never per message); always exits 0 so it never blocks the prompt.

LIB="$(dirname "${BASH_SOURCE[0]}")/lib/cmux-remote.sh"
[[ -f "$LIB" ]] || exit 0
# shellcheck source=/dev/null
source "$LIB"

INPUT=$(cat)

SESSION_ID=$(jq -r '.session_id // empty' <<<"$INPUT")
TRANSCRIPT=$(jq -r '.transcript_path // empty' <<<"$INPUT")
[[ -n "$SESSION_ID" && -n "$TRANSCRIPT" ]] || exit 0

# <config>/projects/<proj>/<id>.jsonl -> <config>
CONFIG_DIR=$(dirname "$(dirname "$(dirname "$TRANSCRIPT")")")
SESSIONS_DIR="$CONFIG_DIR/sessions"
[[ -d "$SESSIONS_DIR" ]] || exit 0

# The session name (.name) is absent until the first /rename — no clobber then.
# `|| true`: an empty *.json glob reaches jq unexpanded and fails the pipeline
# under pipefail (the exact silent-block seen in headless workers).
NAME=$(jq -r --arg sid "$SESSION_ID" \
  'select(.sessionId==$sid) | .name // empty' "$SESSIONS_DIR"/*.json 2>/dev/null | head -1 || true)
[[ -n "$NAME" ]] || exit 0

# Churn guard: everything past here only runs when the name actually changed, so
# the remote ssh round-trips fire on a rename, not on every message.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-cmux-tab"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/$SESSION_ID"
PREV="$(cat "$STATE_FILE" 2>/dev/null || true)"
[[ "$PREV" == "$NAME" ]] && exit 0

# Resolve our cmux surface id.
if cmux_is_local; then
  SURFACE="${CMUX_SURFACE_ID:-}"
  [[ -n "$SURFACE" ]] || exit 0
  # Guard the focused-surface fallback: our id must be a live surface.
  run_cmux --id-format both tree --all 2>/dev/null | grep -qiF "$SURFACE" || exit 0
else
  # Remote: fetch the tree once — both resolution strategies below read it.
  TREE=$(run_cmux --id-format both tree --all 2>/dev/null || true)
  [[ -n "$TREE" ]] || exit 0

  # By title first (one round trip, the steady-state path): the surface whose
  # title holds our last-synced name, or the zellij session name before the
  # first sync. Can't clobber — no match falls through to process resolution.
  needle="${PREV:-${ZELLIJ_SESSION_NAME:-}}"
  SURFACE=""
  if [[ -n "$needle" ]]; then
    SURFACE=$(awk -v n="$needle" '
      /surface surface:/ && index($0, n) {
        if (match($0, /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/)) {
          print substr($0, RSTART, RLENGTH)
          exit
        }
      }' <<<"$TREE" || true)
  fi

  # Title matching breaks whenever anything else renames the tab (the user, a
  # sibling session, cmux titling the surface with the SHORT zellij name — the
  # full-name needle can never substring-match a shorter title) — and the
  # per-session state file doesn't cross a /clear or compact-continue session
  # boundary, so a fresh session in an already-renamed tab was unresolvable.
  # Deterministic fallback: cmux `top` exposes the mac-side process tree per
  # surface, and the mosh-client/zellij command line carries the exact zellij
  # session name ("… mosh-client -# bonbon -- zellij attach <name> | …").
  # Match ours → pid → surface ref → UUID via the tree. Two extra round trips,
  # paid only on this recovery path.
  if [[ -z "$SURFACE" && -n "${ZELLIJ_SESSION_NAME:-}" ]]; then
    pairs=$(run_cmux top --all --processes --flat --format tsv 2>/dev/null |
      awk -F'\t' '$4=="process" && $6 ~ /^surface:/ {print $5 "\t" $6}' || true)
    if [[ -n "$pairs" ]]; then
      pids=$(cut -f1 <<<"$pairs" | paste -sd, -)
      # shellcheck disable=SC2029 # $pids expands client-side by design
      psout=$(ssh -n "$CMUX_APP_HOST" "ps -o pid=,args= -p $pids" 2>/dev/null || true)
      # Session names are [a-z0-9-], so the dynamic regex is literal-safe; the
      # boundary match stops "…-1-x" claiming "…-1-xy".
      owner=$(awk -v n="$ZELLIJ_SESSION_NAME" \
        '$0 ~ ("[ /]" n "( |$)") {print $1; exit}' <<<"$psout" || true)
      if [[ -n "$owner" ]]; then
        ref=$(awk -F'\t' -v p="$owner" '$1==p {print $2; exit}' <<<"$pairs")
        [[ -n "$ref" ]] && SURFACE=$(grep -F "surface $ref " <<<"$TREE" |
          grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' |
          head -1 || true)
      fi
    fi
  fi
  [[ -n "$SURFACE" ]] || exit 0
fi

params=$(jq -nc --arg t "$SURFACE" --arg n "$NAME" '{action:"rename",tab_id:$t,title:$n}')
acted=$(run_cmux rpc tab.action "$params" 2>/dev/null | jq -r '.surface_id // empty' || true)

# Record the sync only if cmux renamed *our* surface (UUIDs, case-insensitive).
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
if [[ -n "$acted" && "$(lc "$acted")" == "$(lc "$SURFACE")" ]]; then
  printf '%s' "$NAME" >"$STATE_FILE"
fi
exit 0
