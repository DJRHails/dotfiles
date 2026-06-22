#!/bin/sh
# Generate the ssh::durable picker menu for a host's live zellij sessions.
#
# Each menu line is tab-separated:
#   <session-name>\t<short-id>  —  <summary>  ·  <cwd>
# field 1 is the exact session name (used to attach / drive the fzf preview);
# field 2 is the human label fzf shows and searches — so the AI summary AND the
# working directory are both fuzzy-searchable.
#
# Runs entirely on the host (single ssh). cwds come from `dump-layout` (cheap,
# local IPC); summaries come from piping the live screen through `claude -p`.
# Both are cached under ~/.cache/durable-summaries and refreshed when older than
# <ttl> seconds, so warm runs are instant.
#
# Modes:
#   --preview <session>              cwd header + live screen, for the fzf preview window
#   --stream  <pfx> <model> <ttl> <par>   progressive picker feed: emit every session
#                                    immediately from cache, then re-emit each line as
#                                    its cwd (fast) and summary (slow) land. The caller
#                                    keeps the latest line per session (keyed on field 1).
#   --list    <pfx> <model> <ttl> <par>   batch: refresh everything, emit the final menu
#                                    once (no progressive re-emits) — for --list/--query.
set -u

cdir="$HOME/.cache/durable-summaries"
prompt='This is the current terminal screen of a dev session. In ONE terse line (max 12 words), say what it is currently doing. No preamble.'
# cwd extraction is local zellij IPC (no API), so fan out much wider than summaries.
cwd_par=16

cwd_of() {  # $1=session  ->  prints cwd with $HOME collapsed to ~
  zellij -s "$1" action dump-layout 2>/dev/null \
    | sed -nE 's/^[[:space:]]*cwd "(.*)"$/\1/p' | head -1 \
    | sed "s|^$HOME|~|"
}

if [ "${1:-}" = "--preview" ]; then
  s="${2:-}"; [ -n "$s" ] || exit 0
  # Title from cache only — preview runs on every cursor move, so it must never call claude.
  sum='?'; [ -s "$cdir/$s" ] && sum=$(cat "$cdir/$s")
  printf '\033[1;36mtitle:\033[0m %s\n' "$sum"
  printf '\033[1;36mcwd:\033[0m   %s\n\n' "$(cwd_of "$s")"
  zellij -s "$s" action dump-screen 2>/dev/null | tail -n 200
  exit 0
fi

mode="${1:-}"
hostpfx="${2:-}"; model="${3:-claude-haiku-4-5}"; ttl="${4:-300}"; par="${5:-8}"
mkdir -p "$cdir"
now=$(date +%s)

# zellij prints sessions oldest-first; reverse to newest-first (no tac on macOS) so the
# menu — and --query/--list, which take the first match — prefer the most recent session.
list_sessions() {
  zellij list-sessions 2>/dev/null \
    | sed -E 's/\x1b\[[0-9;]*m//g' \
    | grep -v 'EXITED' \
    | awk 'NF {a[++n] = $1} END {for (i = n; i > 0; i--) print a[i]}'
}

# 0 (success) if the cache file is missing, empty, or older than $ttl.
stale() {
  [ -s "$1" ] || return 0
  mt=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)
  [ $((now - mt)) -gt "$ttl" ]
}

refresh_cwd() {  # $1=session ; writes $cdir/$1.cwd (atomic)
  c=$(cwd_of "$1")
  [ -n "$c" ] || return 1
  printf '%s\n' "$c" > "$cdir/$1.cwd.tmp" && mv -f "$cdir/$1.cwd.tmp" "$cdir/$1.cwd"
}

run_claude() {  # reads a screen dump on stdin, prints a one-line summary; exit = claude's
  if command -v timeout >/dev/null 2>&1; then
    timeout 60 claude -p --model "$model" "$prompt" 2>/dev/null
  else
    claude -p --model "$model" "$prompt" 2>/dev/null
  fi
}

# Summarise the session's screen. Returns non-zero (and writes nothing) on any failure
# — empty screen, claude error/timeout, or error-shaped output — so an auth failure
# (claude prints "Failed to authenticate…" to stdout and exits 1) is never cached as a title.
summarise() {  # $1=session ; writes $cdir/$1 on success
  screen=$(zellij -s "$1" action dump-screen 2>/dev/null | grep -v '^[[:space:]]*$' | tail -n 40)
  [ -n "$screen" ] || return 1
  out=$(printf '%s\n' "$screen" | run_claude) || return 1
  out=$(printf '%s' "$out" | tr '\n' ' ' | sed 's/  */ /g; s/^ *//; s/ *$//' | cut -c1-90)
  case "$out" in
    '') return 1 ;;
    *'API Error'* | *'authenticate'* | *'Invalid authentication'*) return 1 ;;
  esac
  printf '%s\n' "$out" > "$cdir/$1.tmp" && mv -f "$cdir/$1.tmp" "$cdir/$1"
}

# One cheap probe so an expired/invalid token fails fast instead of hammering every session
# with a doomed call. Returns 0 if claude responds; on failure prints the error text and
# returns 1 (caller decides whether it's auth-shaped).
auth_check() {
  __probe=$(printf 'ping\n' | run_claude) && return 0
  printf '%s' "$__probe"
  return 1
}

# Surface a fatal auth problem: in --stream it's an in-band control line the applier consumes
# (so it never shows as a session); in --list it's a stderr diagnostic (keeps stdout a clean menu).
emit_authfail() {  # $1=message
  if [ "$stream" = 1 ]; then
    printf '__AUTHFAIL__\t%s\n' "$1"
  else
    printf 'DURABLE_AUTH_FAIL: %s\n' "$1" >&2
  fi
}

emit_line() {  # $1=session ; one menu line from cache (placeholders for what's not ready yet)
  sum='?'; [ -s "$cdir/$1" ] && sum=$(cat "$cdir/$1")
  cwd=''; [ -s "$cdir/$1.cwd" ] && cwd=$(cat "$cdir/$1.cwd")
  short=${1#cmux-"${hostpfx}"-}
  if [ -n "$cwd" ]; then
    printf '%s\t%s  —  %s  ·  %s\n' "$1" "$short" "$sum" "$cwd"
  else
    printf '%s\t%s  —  %s\n' "$1" "$short" "$sum"
  fi
}

sessions=$(list_sessions)
[ -n "$sessions" ] || exit 0

stream=0; [ "$mode" = "--stream" ] && stream=1

# Instant list: every session straight from cache (ids + any cached cwd/summary). In
# stream mode this is what the picker shows before any refresh has run.
[ "$stream" = 1 ] && for s in $sessions; do emit_line "$s"; done

# Phase 1 — cwds (cheap local IPC, wide fan-out): fills the working dirs fast.
i=0
for s in $sessions; do
  stale "$cdir/$s.cwd" || continue
  { refresh_cwd "$s"; [ "$stream" = 1 ] && emit_line "$s"; } &
  i=$((i + 1)); [ $((i % cwd_par)) -eq 0 ] && wait
done
wait

# Phase 2 — summaries (API calls, bounded): trickle in as each session is titled.
# Fail fast first: if any titles are due, probe auth once. An auth-shaped failure skips the
# whole fan-out (cwds from phase 1 keep the picker usable) and surfaces a fix-it message.
need_summaries=0
for s in $sessions; do stale "$cdir/$s" && { need_summaries=1; break; }; done

if [ "$need_summaries" = 1 ] && ! probe=$(auth_check); then
  case "$probe" in
    *401* | *authenticate* | *'Invalid authentication'*)
      emit_authfail "claude auth failed on ${hostpfx:-this host} — titles unavailable. fix: ssh -t ${hostpfx:-HOST} claude setup-token"
      need_summaries=0
      ;;
  esac
fi

if [ "$need_summaries" = 1 ]; then
  i=0
  for s in $sessions; do
    stale "$cdir/$s" || continue
    { summarise "$s"; [ "$stream" = 1 ] && emit_line "$s"; } &
    i=$((i + 1)); [ $((i % par)) -eq 0 ] && wait
  done
  wait
fi

# Batch mode: emit the finished menu exactly once.
[ "$stream" = 1 ] || for s in $sessions; do emit_line "$s"; done
