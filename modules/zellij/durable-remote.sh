#!/bin/sh
# Generate the ssh::durable picker menu for a host's live zellij sessions.
#
# Each menu line is tab-separated, three fields:
#   <session-name> \t <●><cwd-fragment>  ·  <3-5 word title> \t <short-id> <full-cwd>
# field 1 is the exact session name (used to attach / drive the fzf preview);
# field 2 is the compact label the picker shows and fuzzy-searches (last two path components +
# a tiny AI title); field 3 is hidden — it carries the full cwd + short-id so the --query/--list
# grep still matches the whole path and session id. The one-line summary lives in the preview.
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
connf="$cdir/.connected"  # cache: sessions with a live mosh client (one name per line)
prompt='This is the current terminal screen of a dev session. Reply with EXACTLY two lines, nothing else.
Line 1: what it is currently doing, one terse line, max 12 words.
Line 2: a 3-5 word title, no trailing punctuation.'
# cwd extraction is local zellij IPC (no API), so fan out much wider than summaries.
cwd_par=16

cwd_of() {  # $1=session  ->  prints cwd with $HOME collapsed to ~
  zellij -s "$1" action dump-layout 2>/dev/null \
    | sed -nE 's/^[[:space:]]*cwd "(.*)"$/\1/p' | head -1 \
    | sed "s|^$HOME|~|"
}

# Last two path components, end-first: ~/projects/github.com/DJRHails/touchstone -> DJRHails/touchstone; ~ -> ~
cwd_frag() {  # $1=cwd
  p="$1"; rest="${p%/*}"
  if [ "$rest" = "$p" ]; then printf '%s\n' "$p"; else printf '%s/%s\n' "${rest##*/}" "${p##*/}"; fi
}

# Dump a session's live screen. `dump-screen` returns the rendered viewport, which is empty for a
# *detached* full-screen TUI (claude/vim) — nothing is rendering the alternate screen. When that
# happens we briefly attach a throwaway client through a sized tmux pty (NOT mosh) to force a
# render, dump, then detach. Sessions that already have a client dump directly and are never
# touched (so an active session is never resized under you). The pty is wide so detached sessions
# aren't shrunk. Best-effort: if tmux is missing we just return whatever dump-screen gave.
dump_screen() {  # $1=session
  out=$(zellij -s "$1" action dump-screen 2>/dev/null)
  case "$out" in *[![:space:]]*) printf '%s\n' "$out"; return 0 ;; esac
  command -v tmux >/dev/null 2>&1 || { printf '%s\n' "$out"; return 0; }
  t="dr-$1"
  # `timeout` is a safety net: if fzf kills this preview mid-render before the kill-session below
  # runs, the transient client still self-detaches instead of becoming a new lingering client.
  attach="zellij attach ${1}"
  command -v timeout >/dev/null 2>&1 && attach="timeout 8 ${attach}"
  tmux kill-session -t "$t" 2>/dev/null
  tmux new-session -d -s "$t" -x 250 -y 60 "$attach" 2>/dev/null || { printf '%s\n' "$out"; return 0; }
  sleep "${DURABLE_RENDER_WAIT:-1}"
  zellij -s "$1" action dump-screen 2>/dev/null
  tmux kill-session -t "$t" 2>/dev/null
}

if [ "${1:-}" = "--preview" ]; then
  s="${2:-}"; [ -n "$s" ] || exit 0
  # Title + cwd from cache (instant, printed first so they show while the screen renders). The
  # preview must not call claude or re-run dump-layout per render (that made the cwd flicker); fall
  # back to a live cwd lookup only when it isn't cached yet.
  sum='?'; [ -s "$cdir/$s" ] && sum=$(cat "$cdir/$s")
  cwd=''; [ -s "$cdir/$s.cwd" ] && cwd=$(cat "$cdir/$s.cwd")
  [ -n "$cwd" ] || cwd=$(cwd_of "$s")
  printf '\033[1;36mtitle:\033[0m %s\n' "$sum"
  printf '\033[1;36mcwd:\033[0m   %s\n\n' "${cwd:-?}"
  dump_screen "$s" | tail -n 200
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

# Summarise the session's screen into a one-liner (line 1, for the preview header → $cdir/$1) and
# a 3-5 word title (line 2, for the picker list → $cdir/$1.title). Returns non-zero and writes
# nothing on any failure — empty screen, claude error/timeout, or error-shaped output — so an auth
# failure (claude prints "Failed to authenticate…" to stdout and exits 1) is never cached.
summarise() {  # $1=session ; writes $cdir/$1 and $cdir/$1.title on success
  screen=$(dump_screen "$1" | grep -v '^[[:space:]]*$' | tail -n 40)
  [ -n "$screen" ] || return 1
  out=$(printf '%s\n' "$screen" | run_claude) || return 1
  case "$out" in
    *'API Error'* | *'authenticate'* | *'Invalid authentication'*) return 1 ;;
  esac
  # first two non-blank lines, tolerating a stray "Line 1:" / "Line 2." prefix from the model
  nb=$(printf '%s' "$out" | grep -v '^[[:space:]]*$' | sed -E 's/^[[:space:]]*[Ll]ine [0-9][:.][[:space:]]*//')
  one=$(printf '%s\n' "$nb" | sed -n '1p' | sed 's/^ *//; s/ *$//' | cut -c1-90)
  tit=$(printf '%s\n' "$nb" | sed -n '2p' | sed 's/^ *//; s/ *$//' | cut -c1-40)
  [ -n "$one" ] || return 1
  [ -n "$tit" ] || tit=$(printf '%s' "$one" | cut -d' ' -f1-4)  # fallback: first words of the one-liner
  printf '%s\n' "$one" > "$cdir/$1.tmp" && mv -f "$cdir/$1.tmp" "$cdir/$1"
  printf '%s\n' "$tit" > "$cdir/$1.title.tmp" && mv -f "$cdir/$1.title.tmp" "$cdir/$1.title"
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

# A session is "connected" if it has a live mosh client. mosh-server keeps a `zellij attach`
# child alive long after the human disconnects, so a process merely existing means nothing —
# but a *connected* mosh-server burns a little CPU on keepalives every ~3s while a dead one
# blocks idle. mosh_phase() samples that and writes the live set to $connf; is_connected reads it.
is_connected() { [ -s "$connf" ] && grep -qxF "$1" "$connf"; }

emit_line() {  # $1=session ; one menu line from cache (placeholders for what's not ready yet)
  tit='?'; [ -s "$cdir/$1.title" ] && tit=$(cat "$cdir/$1.title")
  cwd=''; [ -s "$cdir/$1.cwd" ] && cwd=$(cat "$cdir/$1.cwd")
  short=${1#cmux-"${hostpfx}"-}
  frag='?'; [ -n "$cwd" ] && frag=$(cwd_frag "$cwd")
  ind='  '  # detached: blank, keeping labels aligned with the connected marker
  is_connected "$1" && ind="$(printf '\033[32m●\033[0m ')"  # green ● = a client is attached
  # field 2 = compact display (cwd fragment, then the tiny title); field 3 = hidden, searchable
  printf '%s\t%s%s  ·  %s\t%s %s\n' "$1" "$ind" "$frag" "$tit" "$short" "$cwd"
}

cpu_jiffies() {  # $1=space-separated pids ; prints "pid utime+stime" per pid (no forks)
  for p in $1; do
    read -r line < "/proc/$p/stat" 2>/dev/null || continue
    # shellcheck disable=SC2086  # deliberate word-split of the stat line into positional fields
    set -- $line
    [ "$#" -ge 15 ] && printf '%s %s\n' "$p" "$(( ${14} + ${15} ))"
  done
}

# Refresh the connected-session cache and reap orphaned mosh-servers (the `--reap` mode). A
# mosh-server burns a little CPU on keepalives while a client is connected and is flat once it
# disconnects; sampling twice, $win apart, tells them apart. The window must be generous —
# keepalive work is often sub-jiffie, so short windows misfire — 60s separates live from dead
# cleanly. Live sessions → $connf (drives the picker's green ● + count). Flat servers older than
# $age_min → SIGTERM, which is safe: it only drops the stale mosh transport; the zellij session
# (your actual work) persists and the picker re-moshes a fresh one. Linux-only (needs /proc).
mosh_reap() {
  [ -r /proc/self/stat ] || { printf 'mosh-reap: not Linux, skipping\n' >&2; return 0; }
  win="${1:-60}" age_min=120
  raw=$(pgrep -af 'mosh-server' 2>/dev/null)
  [ -n "$raw" ] || { : > "$connf"; printf 'mosh-reap: no mosh-servers\n' >&2; return 0; }
  pids=$(printf '%s\n' "$raw" | awk '{print $1}')
  # pid -> session, but only for the picker-attach form (`zellij attach <session>`); fresh-path
  # mosh-servers (… zsh -l) can't be name-mapped, so they feed the reaper but not $connf.
  map=$(printf '%s\n' "$raw" | sed -nE 's/^([0-9]+).*zellij attach (-c )?(cmux-[A-Za-z0-9_-]+).*/\1 \3/p')
  s1=$(cpu_jiffies "$pids")
  sleep "$win"
  s2=$(cpu_jiffies "$pids")
  live_pids=$(printf '%s\n%s\n' "$s1" "$s2" \
    | awk '{seen[$1]=seen[$1]" "$2; n[$1]++}
           END {for (p in n) if (n[p] >= 2) {split(seen[p], a, " "); if (a[2] > a[1]) print p}}')
  # live attach-path sessions → cache (atomic)
  printf '%s\n' "$map" | awk -v L="$live_pids" \
    'BEGIN{split(L,a," ");for(i in a)keep[a[i]]=1} ($1 in keep){print $2}' \
    | sort -u > "$connf.tmp" && mv -f "$connf.tmp" "$connf"
  # reap every flat (disconnected) mosh-server old enough to be sure — attach- AND fresh-path
  reaped=$(printf '%s\n' "$pids" | { n=0; while read -r p; do
      case " $live_pids " in *" $p "*) continue ;; esac
      a=$(ps -o etimes= -p "$p" 2>/dev/null | tr -d ' ')
      [ -n "$a" ] && [ "$a" -gt "$age_min" ] 2>/dev/null && kill -TERM "$p" 2>/dev/null && n=$((n + 1))
    done; echo "$n"; })
  printf 'mosh-reap: %s live, %s orphans reaped\n' "$(grep -c . "$connf" 2>/dev/null || echo 0)" "$reaped" >&2
}

# --reap: sample mosh-servers, refresh $connf, kill disconnected ones. Run on its own (it takes
# ~$win seconds); the picker only ever reads the $connf cache it leaves behind. See mosh_reap.
[ "$mode" = "--reap" ] && { mosh_reap "${2:-}"; exit 0; }

sessions=$(list_sessions)
[ -n "$sessions" ] || exit 0

stream=0; [ "$mode" = "--stream" ] && stream=1

# Instant list: every session straight from cache (ids, cached cwd/summary, and ● from the last
# run's $connf). In stream mode this is what the picker shows before any refresh has run.
[ "$stream" = 1 ] && for s in $sessions; do emit_line "$s"; done

# Connected count → picker header (control line, not a row). Straight from the cached live set
# ($connf, refreshed out-of-band by --reap), so it's known immediately like the ● markers.
if [ "$stream" = 1 ]; then
  n_conn=0; for s in $sessions; do is_connected "$s" && n_conn=$((n_conn + 1)); done
  printf '__STATUS__\t%d connected\n' "$n_conn"
fi

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
