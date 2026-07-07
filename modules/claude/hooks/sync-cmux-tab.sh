#!/bin/bash
set -Eeuo pipefail
# A non-zero hook exit can BLOCK the triggering event (and once stranded headless
# gantry workers when this hook died under set -e). Fail open: any unexpected
# error is a silent no-op.
trap 'exit 0' ERR
# Hook (Stop): keep the cmux panel (the per-surface tab in a pane's tab bar) in
# step with the Claude session name (set by /rename). cmux already syncs the
# *workspace* name; the panel/surface tab is not, so we do it.
#
# Stateless by design. The old per-session state cache recorded what we last SET
# and treated that as proof of what the tab still SHOWS — a cmux restart or any
# out-of-band rename clobbered the title while the cache claimed synced-ness, so
# tabs went stale forever. Now every Stop re-reads reality and converges:
# steady state costs one transport round trip (tree); an actual rename costs
# four (tree, top, ps, tab.action).
#
# Event choice — UserPromptSubmit + Stop: /rename is a client-side metadata
# command that fires NO hook of its own (verified on v2.1.196, like /model), so
# we sync on the next event. UserPromptSubmit lands the rename the moment the
# user types again (author preference — worth the ~0.3s steady-state round trip
# per prompt); Stop is the backstop for turns that end without another prompt.
# Stop does NOT fire on an interrupted turn, which is exactly why prompt-submit
# matters. The in-script gate rejects any other event a future settings change
# might add (e.g. SessionStart).
#
# Every run appends one line to $XDG_STATE_HOME/claude-cmux-tab/sync.log
# (event, session, name, outcome, duration) — stdout stays silent because a
# UserPromptSubmit hook's stdout is injected into the model's context.
#
# Fork safety: cmux-fork-session titles a fork's tab "fork: <NAME>" while the
# fork *inherits* NAME — the sync must not clobber that. Rule: a terminal tab
# whose title CONTAINS the session name is already in sync (exact match or
# fork-prefixed) — no rename. This replaces the old fork pre-seed of the state
# cache. Cost of the rule: a *different* terminal tab titled with our exact
# session name suppresses our sync (rare, benign, self-corrects on the next
# distinct rename).
#
# Local vs remote (this hook runs wherever `claude` runs):
#   - Local (the cmux UI host): cmux injects a fresh, reliable $CMUX_SURFACE_ID.
#   - Remote (durable/mosh box with no cmux, e.g. bonbon): $CMUX_SURFACE_ID is
#     stale — resolve deterministically instead: cmux `top` exposes the
#     UI-host-side pid per surface, and the mosh-client/zellij command line
#     carries the exact zellij session name ("… mosh-client -# bonbon -- zellij
#     attach <name> | …"); match ours → pid → surface ref → UUID via the tree.
#
# Rename uses the `tab.action` JSON-RPC, not `cmux rename-tab`: the subcommand
# fails with "Tab not found" on current cmux builds and the remote relay lacks
# it. tab.action silently falls back to renaming the *focused* surface on an
# unresolvable tab_id, so we confirm cmux acted on *our* surface afterwards.
#
# Manual invocation (debugging / one-shot repair of another session's tab): the
# process resolution keys on the INVOKER's $ZELLIJ_SESSION_NAME, so running this
# by hand for a different session renames YOUR tab unless you override it:
#   printf '{"session_id":"<sid>","transcript_path":"<path>"}' \
#     | ZELLIJ_SESSION_NAME=<that session's zellij name> bash sync-cmux-tab.sh
# (Omitting hook_event_name defaults to Stop, so manual runs are not gated.)
#
# Robust: silent no-op on non-Stop events, outside cmux, before any /rename, or
# if the transport is unreachable; always exits 0 so it never blocks anything.

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-cmux-tab"
LOG_FILE="$LOG_DIR/sync.log"
START="${EPOCHREALTIME:-}" # bash ≥5; empty on macOS /bin/bash 3.2 → duration omitted
log() {
  mkdir -p "$LOG_DIR" 2>/dev/null || return 0
  # Size-capped rotation, one generation.
  [[ -n "$(find "$LOG_FILE" -size +1M 2>/dev/null)" ]] && mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null
  local dur=""
  [[ -n "$START" && -n "${EPOCHREALTIME:-}" ]] &&
    dur=" dur_ms=$(awk -v a="$START" -v b="$EPOCHREALTIME" 'BEGIN{printf "%d", (b-a)*1000}')"
  printf '%s evt=%s sid=%s name=%s %s%s\n' "$(date -u +%FT%TZ)" \
    "${EVENT:-?}" "${SESSION_ID:-?}" "${NAME:-}" "$*" "$dur" >>"$LOG_FILE" 2>/dev/null || true
}
finish() {
  log "$1"
  exit 0
}
trap 'log "outcome=unexpected-error line=$LINENO"; exit 0' ERR

LIB="$(dirname "${BASH_SOURCE[0]}")/lib/cmux-remote.sh"
[[ -f "$LIB" ]] || finish "outcome=no-lib"
# shellcheck source=/dev/null
source "$LIB"

INPUT=$(cat)

EVENT=$(jq -r '.hook_event_name // "Stop"' <<<"$INPUT")
[[ "$EVENT" == "Stop" || "$EVENT" == "UserPromptSubmit" ]] || finish "outcome=gated-event"

SESSION_ID=$(jq -r '.session_id // empty' <<<"$INPUT")
TRANSCRIPT=$(jq -r '.transcript_path // empty' <<<"$INPUT")
[[ -n "$SESSION_ID" && -n "$TRANSCRIPT" ]] || finish "outcome=no-session-meta"

# <config>/projects/<proj>/<id>.jsonl -> <config>
CONFIG_DIR=$(dirname "$(dirname "$(dirname "$TRANSCRIPT")")")
SESSIONS_DIR="$CONFIG_DIR/sessions"
[[ -d "$SESSIONS_DIR" ]] || finish "outcome=no-sessions-dir"

# The session name (.name) is absent until the first /rename — nothing to sync.
# `|| true`: an empty *.json glob reaches jq unexpanded and fails the pipeline
# under pipefail (the exact silent-block once seen in headless workers).
NAME=$(jq -r --arg sid "$SESSION_ID" \
  'select(.sessionId==$sid) | .name // empty' "$SESSIONS_DIR"/*.json 2>/dev/null | head -1 || true)
[[ -n "$NAME" ]] || finish "outcome=no-name"

# One tree fetch serves the in-sync check, the ref→UUID map, and the liveness
# guard on the local branch.
TREE=$(run_cmux --id-format both tree --all 2>/dev/null || true)
[[ -n "$TREE" ]] || finish "outcome=no-tree"

# In-sync shortcut (and the fork rule): a live *terminal* tab already titled
# with the session name — exactly, or as a prefixed form like "fork: <name>" —
# means there is nothing to do. The match is boundary-anchored on the quoted
# title, not a raw substring: renaming "abstract-iteration-2" back to
# "abstract-iteration" must NOT count the old title as in sync (substring
# would), and a title merely *containing* the name mid-word must not either.
if awk -v n="$NAME" '
  /surface surface:/ && /\[terminal\]/ && match($0, /"[^"]*"/) {
    t = substr($0, RSTART + 1, RLENGTH - 2)
    if (t == n) { found = 1; exit }
    if (length(t) > length(n) && substr(t, length(t) - length(n) + 1) == n &&
        substr(t, length(t) - length(n), 1) !~ /[A-Za-z0-9-]/) { found = 1; exit }
  }
  END { exit !found }' <<<"$TREE"; then
  finish "outcome=in-sync"
fi

# Resolve our cmux surface id.
if cmux_is_local; then
  SURFACE="${CMUX_SURFACE_ID:-}"
  [[ -n "$SURFACE" ]] || finish "outcome=local-no-surface-env"
  # Guard the focused-surface fallback: our id must be a live surface.
  grep -qiF "$SURFACE" <<<"$TREE" || finish "outcome=local-stale-surface"
else
  [[ -n "${ZELLIJ_SESSION_NAME:-}" ]] || finish "outcome=no-zellij-env"
  pairs=$(run_cmux top --all --processes --flat --format tsv 2>/dev/null |
    awk -F'\t' '$4=="process" && $6 ~ /^surface:/ {print $5 "\t" $6}' || true)
  [[ -n "$pairs" ]] || finish "outcome=no-surface-processes"
  pids=$(cut -f1 <<<"$pairs" | paste -sd, -)
  # shellcheck disable=SC2029 # $pids expands client-side by design
  psout=$(ssh -n "$CMUX_APP_HOST" "ps -o pid=,args= -p $pids" 2>/dev/null || true)
  # Session names are [a-z0-9-], so the dynamic regex is literal-safe; the
  # boundary match stops "…-1-x" claiming "…-1-xy".
  owner=$(awk -v n="$ZELLIJ_SESSION_NAME" \
    '$0 ~ ("[ /]" n "( |$)") {print $1; exit}' <<<"$psout" || true)
  [[ -n "$owner" ]] || finish "outcome=zellij-session-not-found zellij=$ZELLIJ_SESSION_NAME"
  ref=$(awk -F'\t' -v p="$owner" '$1==p {print $2; exit}' <<<"$pairs")
  [[ -n "$ref" ]] || finish "outcome=no-surface-ref pid=$owner"
  SURFACE=$(grep -F "surface $ref " <<<"$TREE" |
    grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' |
    head -1 || true)
  [[ -n "$SURFACE" ]] || finish "outcome=no-surface-uuid ref=$ref"
fi

params=$(jq -nc --arg t "$SURFACE" --arg n "$NAME" '{action:"rename",tab_id:$t,title:$n}')
acted=$(run_cmux rpc tab.action "$params" 2>/dev/null | jq -r '.surface_id // empty' || true)

# Confirm cmux renamed *our* surface (UUIDs, case-insensitive) — a mismatch
# means the focused-surface fallback fired; nothing we can do but not lie.
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
[[ -n "$acted" && "$(lc "$acted")" == "$(lc "$SURFACE")" ]] ||
  finish "outcome=rename-unverified surface=$SURFACE acted=${acted:-none}"
finish "outcome=renamed surface=$SURFACE"
